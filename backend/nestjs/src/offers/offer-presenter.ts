import type { Prisma } from "@prisma/client";
import { endDateOf, offerStatus, startDateOf } from "./offer-dates";

/// Loads only whether an image exists, never its bytes.
export const OFFER_IMAGE_FLAG = {
  image: { select: { offerId: true } },
} satisfies Prisma.StoreOfferInclude;

export type OfferWithImageFlag = Prisma.StoreOfferGetPayload<{
  include: typeof OFFER_IMAGE_FLAG;
}>;

/// displayOrder ascending, then newest first.
export const OFFER_ORDER: Prisma.StoreOfferOrderByWithRelationInput[] = [
  { displayOrder: "asc" },
  { createdAt: "desc" },
];

function validity(offer: OfferWithImageFlag) {
  return {
    // Inclusive Asia/Damascus calendar days, as the admin entered them.
    startDate: startDateOf(offer.startsAt),
    endDate: endDateOf(offer.endsBefore),
    // The stored UTC instants: startsAt inclusive, endsBefore EXCLUSIVE.
    startsAt: offer.startsAt?.toISOString() ?? null,
    endsBefore: offer.endsBefore?.toISOString() ?? null,
  };
}

/// Customer-facing shape. Image URLs are relative to the API base URL and
/// versioned for cache-busting; image bytes are never included.
export function presentPublicOffer(offer: OfferWithImageFlag) {
  return {
    id: offer.id,
    storeId: offer.storeId,
    title: offer.title,
    description: offer.description,
    discountLabel: offer.discountLabel,
    imageUrl: offer.image
      ? `/offers/${offer.id}/image?v=${offer.imageVersion}`
      : null,
    ...validity(offer),
  };
}

/// Admin shape: everything, including inactive/scheduled/expired offers.
/// The admin image URL serves the image regardless of the offer's status.
export function presentAdminOffer(offer: OfferWithImageFlag, now: Date) {
  return {
    id: offer.id,
    storeId: offer.storeId,
    title: offer.title,
    description: offer.description,
    discountLabel: offer.discountLabel,
    hasImage: offer.image !== null,
    imageVersion: offer.imageVersion,
    imageUrl: offer.image
      ? `/admin/offers/${offer.id}/image?v=${offer.imageVersion}`
      : null,
    ...validity(offer),
    isActive: offer.isActive,
    displayOrder: offer.displayOrder,
    status: offerStatus(offer, now),
    createdAt: offer.createdAt.toISOString(),
    updatedAt: offer.updatedAt.toISOString(),
  };
}
