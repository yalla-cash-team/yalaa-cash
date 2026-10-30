import { BadRequestException } from "@nestjs/common";
import { MAX_STORE_LOGO_BYTES, decodeStoreLogo } from "../src/stores/store-logo";

const PNG_BASE64 = Buffer.from([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00,
]).toString("base64");
const JPEG_BASE64 = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00]).toString(
  "base64",
);
const WEBP_BASE64 = Buffer.from("RIFF0000WEBPVP8 ", "ascii").toString("base64");

describe("decodeStoreLogo", () => {
  it("accepts PNG, JPEG and WebP logos with matching content", () => {
    expect(decodeStoreLogo("image/png", PNG_BASE64).contentType).toBe(
      "image/png",
    );
    expect(decodeStoreLogo("image/jpeg", JPEG_BASE64).data.length).toBe(5);
    expect(decodeStoreLogo("image/webp", WEBP_BASE64).data.length).toBe(16);
  });

  it("rejects unsupported content types", () => {
    expect(() => decodeStoreLogo("image/gif", PNG_BASE64)).toThrow(
      BadRequestException,
    );
    expect(() => decodeStoreLogo("constructor", PNG_BASE64)).toThrow(
      BadRequestException,
    );
  });

  it("rejects a file whose bytes do not match the declared type", () => {
    expect(() => decodeStoreLogo("image/jpeg", PNG_BASE64)).toThrow(
      BadRequestException,
    );
  });

  it("rejects malformed base64 and empty data", () => {
    expect(() => decodeStoreLogo("image/png", "not base64!")).toThrow(
      BadRequestException,
    );
    expect(() => decodeStoreLogo("image/png", "")).toThrow(
      BadRequestException,
    );
  });

  it("rejects logos above the size limit", () => {
    const oversized = Buffer.alloc(MAX_STORE_LOGO_BYTES + 1);
    oversized.set([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a], 0);

    expect(() =>
      decodeStoreLogo("image/png", oversized.toString("base64")),
    ).toThrow(BadRequestException);
  });
});
