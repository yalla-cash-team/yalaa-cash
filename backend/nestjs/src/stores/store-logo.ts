import { BadRequestException } from "@nestjs/common";

export const MAX_STORE_LOGO_BYTES = 300 * 1024;

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const BASE64_PATTERN = /^[A-Za-z0-9+/]+={0,2}$/;

// Checks the file's leading bytes so a declared content type cannot lie.
const SIGNATURE_CHECKS = new Map<string, (data: Buffer) => boolean>([
  ["image/png", (data) => data.subarray(0, 8).equals(PNG_SIGNATURE)],
  [
    "image/jpeg",
    (data) => data[0] === 0xff && data[1] === 0xd8 && data[2] === 0xff,
  ],
  [
    "image/gif",
    (data) =>
      data.subarray(0, 6).toString("ascii") === "GIF87a" ||
      data.subarray(0, 6).toString("ascii") === "GIF89a",
  ],
  [
    "image/webp",
    (data) =>
      data.subarray(0, 4).toString("ascii") === "RIFF" &&
      data.subarray(8, 12).toString("ascii") === "WEBP",
  ],
]);

export interface StoreLogoPayload {
  contentType: string;
  data: Uint8Array<ArrayBuffer>;
}

/// Validates a base64-encoded store logo and returns its decoded bytes.
export function decodeStoreLogo(
  contentType: string,
  dataBase64: string,
): StoreLogoPayload {
  const signatureCheck = SIGNATURE_CHECKS.get(contentType);
  if (!signatureCheck) {
    throw new BadRequestException("Logo must be a PNG, JPEG or WebP image.");
  }
  if (!BASE64_PATTERN.test(dataBase64)) {
    throw new BadRequestException("Logo data must be base64 encoded.");
  }

  const bytes = Buffer.from(dataBase64, "base64");
  if (bytes.length === 0 || bytes.length > MAX_STORE_LOGO_BYTES) {
    throw new BadRequestException("Logo must be at most 300 KB.");
  }
  if (!signatureCheck(bytes)) {
    throw new BadRequestException("Logo file content does not match its type.");
  }

  return { contentType, data: new Uint8Array(bytes) };
}
