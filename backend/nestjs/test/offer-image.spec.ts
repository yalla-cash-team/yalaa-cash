import { BadRequestException } from "@nestjs/common";
import {
  decodeOfferImage,
  MAX_OFFER_IMAGE_BYTES,
} from "../src/offers/offer-image";
import { decodeStoreLogo } from "../src/stores/store-logo";
import { gifBytes, jpegBytes, pngBytes, webpBytes } from "./support/fake-offers-prisma";

const b64 = (bytes: Buffer) => bytes.toString("base64");

describe("decodeOfferImage", () => {
  it.each([
    ["image/png", pngBytes()],
    ["image/jpeg", jpegBytes()],
    ["image/webp", webpBytes()],
  ])("accepts a real %s file", (type, bytes) => {
    const image = decodeOfferImage(type, b64(bytes));
    expect(image.contentType).toBe(type);
    expect(Buffer.from(image.data).equals(bytes)).toBe(true);
  });

  it("rejects GIF even with a valid GIF signature (offers allow PNG/JPEG/WebP only)", () => {
    expect(() => decodeOfferImage("image/gif", b64(gifBytes()))).toThrow(
      "Offer image must be a PNG, JPEG or WebP image.",
    );
  });

  it.each(["image/svg+xml", "text/html", "application/octet-stream", "", "IMAGE/PNG"])(
    "rejects the content type %p",
    (type) => {
      expect(() => decodeOfferImage(type, b64(pngBytes()))).toThrow(BadRequestException);
    },
  );

  it("accepts exactly 300 KB and rejects one byte more", () => {
    expect(MAX_OFFER_IMAGE_BYTES).toBe(300 * 1024);
    expect(() =>
      decodeOfferImage("image/png", b64(pngBytes(MAX_OFFER_IMAGE_BYTES))),
    ).not.toThrow();
    expect(() =>
      decodeOfferImage("image/png", b64(pngBytes(MAX_OFFER_IMAGE_BYTES + 1))),
    ).toThrow("Offer image must be at most 300 KB.");
  });

  it("rejects an empty payload", () => {
    expect(() => decodeOfferImage("image/png", "")).toThrow(BadRequestException);
  });

  it.each([
    ["a data URL", `data:image/png;base64,${b64(pngBytes())}`],
    ["non-base64 characters", "!!!!"],
    ["embedded whitespace", `${b64(pngBytes()).slice(0, 8)} ${b64(pngBytes()).slice(8)}`],
    ["a truncated (non multiple of 4) payload", b64(pngBytes()).slice(0, -1)],
    ["misplaced padding", "iVBO=w0KGgo="],
  ])("rejects invalid base64: %s", (_label, value) => {
    expect(() => decodeOfferImage("image/png", value)).toThrow(
      "Offer image data must be base64 encoded.",
    );
  });

  it("checks the real file signature, not the declared type", () => {
    expect(() => decodeOfferImage("image/png", b64(jpegBytes()))).toThrow(
      "Offer image file content does not match its type.",
    );
    expect(() => decodeOfferImage("image/jpeg", b64(pngBytes()))).toThrow(
      "Offer image file content does not match its type.",
    );
    expect(() => decodeOfferImage("image/webp", b64(gifBytes()))).toThrow(
      "Offer image file content does not match its type.",
    );
    expect(() =>
      decodeOfferImage("image/png", b64(Buffer.from("<svg onload=alert(1)>"))),
    ).toThrow("Offer image file content does not match its type.");
  });
});

describe("decodeStoreLogo after the shared-validator refactor", () => {
  it("still accepts GIF for logos, banners and products", () => {
    expect(decodeStoreLogo("image/gif", b64(gifBytes())).contentType).toBe("image/gif");
  });

  it("keeps its original error messages", () => {
    expect(() => decodeStoreLogo("image/svg+xml", b64(pngBytes()))).toThrow(
      "Logo must be a PNG, JPEG or WebP image.",
    );
    expect(() => decodeStoreLogo("image/png", "!!!")).toThrow(
      "Logo data must be base64 encoded.",
    );
    expect(() => decodeStoreLogo("image/png", b64(pngBytes(300 * 1024 + 1)))).toThrow(
      "Logo must be at most 300 KB.",
    );
    expect(() => decodeStoreLogo("image/png", b64(jpegBytes()))).toThrow(
      "Logo file content does not match its type.",
    );
  });

  it("keeps its lenient base64 length handling", () => {
    // Unpadded base64 was accepted before the refactor; it still is.
    const unpadded = b64(pngBytes(10)).replace(/=+$/, "");
    expect(unpadded.length % 4).not.toBe(0);
    expect(() => decodeStoreLogo("image/png", unpadded)).not.toThrow();
  });
});
