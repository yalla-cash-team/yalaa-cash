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

/// Rules for one kind of uploaded image (store logo, offer image, ...).
export interface ImageUploadRules {
  /// Content types this kind of image accepts; each must have a signature check.
  allowedTypes: readonly string[];
  /// Prefix used in error messages, e.g. "Logo" or "Offer image".
  label: string;
  maxBytes: number;
  /// Also require canonical base64 length (a multiple of 4, padding included),
  /// so truncated or non-standard payloads are rejected instead of being
  /// decoded leniently.
  strictBase64?: boolean;
}

/// Content types accepted for store logos, product and banner images.
/// Unchanged from before the shared validator existed (GIF included).
export const STORE_LOGO_CONTENT_TYPES: readonly string[] = [
  "image/png",
  "image/jpeg",
  "image/gif",
  "image/webp",
];

/// Validates a base64-encoded image against [rules] and returns its decoded
/// bytes: declared type allowed, base64 well formed, size within the cap, and
/// the file's leading bytes matching the declared type.
export function decodeImageUpload(
  contentType: string,
  dataBase64: string,
  rules: ImageUploadRules,
): StoreLogoPayload {
  const { label } = rules;
  const signatureCheck = rules.allowedTypes.includes(contentType)
    ? SIGNATURE_CHECKS.get(contentType)
    : undefined;
  if (!signatureCheck) {
    throw new BadRequestException(`${label} must be a PNG, JPEG or WebP image.`);
  }
  if (
    !BASE64_PATTERN.test(dataBase64) ||
    (rules.strictBase64 && dataBase64.length % 4 !== 0)
  ) {
    throw new BadRequestException(`${label} data must be base64 encoded.`);
  }

  const bytes = Buffer.from(dataBase64, "base64");
  if (bytes.length === 0 || bytes.length > rules.maxBytes) {
    throw new BadRequestException(
      `${label} must be at most ${Math.floor(rules.maxBytes / 1024)} KB.`,
    );
  }
  if (!signatureCheck(bytes)) {
    throw new BadRequestException(`${label} file content does not match its type.`);
  }

  return { contentType, data: new Uint8Array(bytes) };
}

/// Validates a base64-encoded store logo and returns its decoded bytes.
export function decodeStoreLogo(
  contentType: string,
  dataBase64: string,
): StoreLogoPayload {
  return decodeImageUpload(contentType, dataBase64, {
    allowedTypes: STORE_LOGO_CONTENT_TYPES,
    label: "Logo",
    maxBytes: MAX_STORE_LOGO_BYTES,
  });
}
