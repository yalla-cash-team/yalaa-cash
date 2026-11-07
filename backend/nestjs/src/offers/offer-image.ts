import {
  decodeImageUpload,
  type StoreLogoPayload,
} from "../stores/store-logo";

export const MAX_OFFER_IMAGE_BYTES = 300 * 1024;

/// Offers accept PNG, JPEG and WebP only (no GIF, unlike store logos).
export const OFFER_IMAGE_CONTENT_TYPES: readonly string[] = [
  "image/png",
  "image/jpeg",
  "image/webp",
];

/// Validates a base64 offer image: allowed type, canonical base64, at most
/// 300 KB decoded, and file signature matching the declared type.
export function decodeOfferImage(
  contentType: string,
  dataBase64: string,
): StoreLogoPayload {
  return decodeImageUpload(contentType, dataBase64, {
    allowedTypes: OFFER_IMAGE_CONTENT_TYPES,
    label: "Offer image",
    maxBytes: MAX_OFFER_IMAGE_BYTES,
    strictBase64: true,
  });
}
