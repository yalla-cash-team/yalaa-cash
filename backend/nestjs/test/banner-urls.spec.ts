import { plainToInstance } from "class-transformer";
import { validate } from "class-validator";
import { CreateBannerDto } from "../src/admin/dto/admin.dto";
import { decodeStoreLogo } from "../src/stores/store-logo";

async function errorsOn(field: "imageUrl" | "targetUrl", value: string) {
  const dto = plainToInstance(CreateBannerDto, {
    title: "Banner",
    imageUrl: "https://cdn.example.com/banner.jpg",
    displayOrder: 1,
    [field]: value,
  });
  return (await validate(dto)).some((e) => e.property === field);
}

describe("banner destination (targetUrl) validation", () => {
  it.each([
    "https://shop.example.com/offer?ref=yalla&utm_source=app",
    "http://example.com/promo",
    "https://example.com/path?sig=abc123%2Fdef&expires=1893456000",
  ])("accepts an external http(s) link: %s", async (url) => {
    expect(await errorsOn("targetUrl", url)).toBe(false);
  });

  it.each([
    "javascript:alert(1)",
    "file:///etc/passwd",
    "data:text/html,hello",
    "/stores?category=restaurants",
  ])("rejects an unsafe or internal target: %s", async (url) => {
    expect(await errorsOn("targetUrl", url)).toBe(true);
  });

  it("rejects a target longer than the 2048-character limit", async () => {
    const long = `https://example.com/?q=${"a".repeat(2100)}`;
    expect(await errorsOn("targetUrl", long)).toBe(true);
  });
});

describe("banner image URL limits", () => {
  it("accepts a long signed CDN image URL (over 500 characters)", async () => {
    const signed = `https://cdn.example.com/banner.jpg?${"sig=abc&".repeat(80)}`;
    expect(signed.length).toBeGreaterThan(500);
    expect(await errorsOn("imageUrl", signed)).toBe(false);
  });

  it("rejects an image URL with a javascript: scheme", async () => {
    expect(await errorsOn("imageUrl", "javascript:alert(1)")).toBe(true);
  });
});

describe("banner GIF uploads", () => {
  it("accepts GIF87a and GIF89a content for the image/gif type", () => {
    const gif89 = Buffer.from("GIF89a\x01\x00\x01\x00", "binary").toString(
      "base64",
    );
    const gif87 = Buffer.from("GIF87a\x01\x00\x01\x00", "binary").toString(
      "base64",
    );
    expect(decodeStoreLogo("image/gif", gif89).contentType).toBe("image/gif");
    expect(decodeStoreLogo("image/gif", gif87).contentType).toBe("image/gif");
  });

  it("rejects a PNG payload declared as GIF", () => {
    const png = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    expect(() => decodeStoreLogo("image/gif", png.toString("base64"))).toThrow();
  });
});
