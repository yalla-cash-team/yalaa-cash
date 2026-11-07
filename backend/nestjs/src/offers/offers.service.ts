import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { PrismaService } from "../prisma/prisma.service";
import type {
  CreateStoreOfferDto,
  UpdateStoreOfferDto,
  UploadOfferImageDto,
} from "./dto/store-offer.dto";
import { resolveOfferWindow } from "./offer-dates";
import { decodeOfferImage } from "./offer-image";
import {
  OFFER_IMAGE_FLAG,
  OFFER_ORDER,
  presentAdminOffer,
  presentPublicOffer,
} from "./offer-presenter";

const OFFER_NOT_FOUND = "Offer was not found.";
const STORE_NOT_FOUND = "Store was not found.";

/// The single definition of "a customer may see this offer now": the offer
/// is switched on, its store is active (stores are soft-deleted via
/// isActive=false) and now is inside [startsAt, endsBefore).
export function publiclyVisibleOfferWhere(now: Date): Prisma.StoreOfferWhereInput {
  return {
    isActive: true,
    store: { isActive: true },
    AND: [
      { OR: [{ startsAt: null }, { startsAt: { lte: now } }] },
      { OR: [{ endsBefore: null }, { endsBefore: { gt: now } }] },
    ],
  };
}

/// Empty or whitespace-only labels are stored as "no label".
function normalizeLabel(label: string | null | undefined): string | null {
  return label ? label : null;
}

/// View-only store offers. Nothing here touches points, cash, redemptions or
/// any Store column: offers reference a store, they never modify it.
@Injectable()
export class OffersService {
  constructor(private readonly prisma: PrismaService) {}

  // ---------------------------------------------------------------- admin

  /// Every offer of the store, including inactive, scheduled and expired ones.
  async listStoreOffersForAdmin(storeId: string, now = new Date()) {
    await this.assertStoreExists(storeId);
    const offers = await this.prisma.storeOffer.findMany({
      where: { storeId },
      orderBy: OFFER_ORDER,
      include: OFFER_IMAGE_FLAG,
    });
    return offers.map((offer) => presentAdminOffer(offer, now));
  }

  async createOffer(storeId: string, dto: CreateStoreOfferDto, now = new Date()) {
    // Validate everything before any write.
    const window = resolveOfferWindow(
      { startsAt: null, endsBefore: null },
      { startDate: dto.startDate, endDate: dto.endDate },
    );
    await this.assertStoreExists(storeId);

    const offer = await this.withOfferErrors(() =>
      this.prisma.storeOffer.create({
        data: {
          storeId,
          title: dto.title,
          description: dto.description ?? "",
          discountLabel: normalizeLabel(dto.discountLabel),
          startsAt: window.startsAt,
          endsBefore: window.endsBefore,
          isActive: dto.isActive ?? true,
          displayOrder: dto.displayOrder ?? 0,
        },
        include: OFFER_IMAGE_FLAG,
      }),
    );
    return presentAdminOffer(offer, now);
  }

  /// Partial update: only the fields present in [dto] change. The date
  /// window is validated as it will be stored (new values merged with the
  /// current ones).
  async updateOffer(offerId: string, dto: UpdateStoreOfferDto, now = new Date()) {
    const current = await this.findOfferOrThrow(offerId);

    const data: Prisma.StoreOfferUpdateInput = {};
    if (dto.title !== undefined) data.title = dto.title;
    if (dto.description !== undefined) data.description = dto.description ?? "";
    if (dto.discountLabel !== undefined) {
      data.discountLabel = normalizeLabel(dto.discountLabel);
    }
    if (dto.isActive !== undefined) data.isActive = dto.isActive;
    if (dto.displayOrder !== undefined) data.displayOrder = dto.displayOrder;
    if (dto.startDate !== undefined || dto.endDate !== undefined) {
      const window = resolveOfferWindow(current, {
        startDate: dto.startDate,
        endDate: dto.endDate,
      });
      data.startsAt = window.startsAt;
      data.endsBefore = window.endsBefore;
    }

    if (Object.keys(data).length === 0) {
      return presentAdminOffer(current, now);
    }
    const updated = await this.withOfferErrors(() =>
      this.prisma.storeOffer.update({
        where: { id: offerId },
        data,
        include: OFFER_IMAGE_FLAG,
      }),
    );
    return presentAdminOffer(updated, now);
  }

  /// Deletes exactly one offer, addressed by its own id (its image is
  /// removed with it by the foreign key cascade). Never a bulk delete.
  async deleteOffer(offerId: string) {
    const current = await this.findOfferOrThrow(offerId);
    await this.withOfferErrors(() =>
      this.prisma.storeOffer.delete({ where: { id: offerId } }),
    );
    return { id: offerId, storeId: current.storeId, deleted: true };
  }

  // Validates the image first (type, size, signature) so nothing is written
  // for an invalid file.
  async setOfferImage(offerId: string, dto: UploadOfferImageDto, now = new Date()) {
    const image = decodeOfferImage(dto.contentType, dto.dataBase64);
    await this.findOfferOrThrow(offerId);

    const updated = await this.withOfferErrors(() =>
      this.prisma.storeOffer.update({
        where: { id: offerId },
        data: {
          imageVersion: { increment: 1 },
          image: {
            upsert: {
              create: { contentType: image.contentType, data: image.data },
              update: { contentType: image.contentType, data: image.data },
            },
          },
        },
        include: OFFER_IMAGE_FLAG,
      }),
    );
    return presentAdminOffer(updated, now);
  }

  async removeOfferImage(offerId: string, now = new Date()) {
    await this.findOfferOrThrow(offerId);

    const [, updated] = await this.withOfferErrors(() =>
      this.prisma.$transaction([
        this.prisma.storeOfferImage.deleteMany({ where: { offerId } }),
        this.prisma.storeOffer.update({
          where: { id: offerId },
          data: { imageVersion: { increment: 1 } },
          include: OFFER_IMAGE_FLAG,
        }),
      ]),
    );
    return presentAdminOffer(updated, now);
  }

  /// Admin preview of an offer image whatever the offer's status.
  async getOfferImageForAdmin(offerId: string) {
    const image = await this.prisma.storeOfferImage.findUnique({
      where: { offerId },
      select: { contentType: true, data: true },
    });
    if (!image) throw new NotFoundException("Offer image was not found.");
    return image;
  }

  // --------------------------------------------------------------- public

  /// Offers a customer can see now. 404 when the store does not exist or is
  /// inactive; an empty list when an active store has no available offers.
  async listPublicStoreOffers(storeId: string, now = new Date()) {
    const store = await this.prisma.store.findFirst({
      where: { id: storeId, isActive: true },
      select: { id: true },
    });
    if (!store) throw new NotFoundException(STORE_NOT_FOUND);

    const offers = await this.prisma.storeOffer.findMany({
      where: { storeId, ...publiclyVisibleOfferWhere(now) },
      orderBy: OFFER_ORDER,
      include: OFFER_IMAGE_FLAG,
    });
    return offers.map(presentPublicOffer);
  }

  /// Image of a currently visible offer only: images of inactive, scheduled
  /// or expired offers, or of inactive stores, are not served publicly.
  async getPublicOfferImage(offerId: string, now = new Date()) {
    const offer = await this.prisma.storeOffer.findFirst({
      where: { id: offerId, ...publiclyVisibleOfferWhere(now) },
      select: { image: { select: { contentType: true, data: true } } },
    });
    if (!offer?.image) throw new NotFoundException("Offer image was not found.");
    return offer.image;
  }

  // -------------------------------------------------------------- helpers

  private async assertStoreExists(storeId: string): Promise<void> {
    const store = await this.prisma.store.findUnique({
      where: { id: storeId },
      select: { id: true },
    });
    if (!store) throw new NotFoundException(STORE_NOT_FOUND);
  }

  private async findOfferOrThrow(offerId: string) {
    const offer = await this.prisma.storeOffer.findUnique({
      where: { id: offerId },
      include: OFFER_IMAGE_FLAG,
    });
    if (!offer) throw new NotFoundException(OFFER_NOT_FOUND);
    return offer;
  }

  /// Maps races (offer deleted concurrently) and the database's window CHECK
  /// constraint to proper HTTP errors instead of 500s.
  private async withOfferErrors<T>(operation: () => Promise<T>): Promise<T> {
    try {
      return await operation();
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError) {
        if (error.code === "P2025") throw new NotFoundException(OFFER_NOT_FOUND);
        if (error.code === "P2003") throw new NotFoundException(STORE_NOT_FOUND);
      }
      if (
        error instanceof Error &&
        error.message.includes("StoreOffer_window_check")
      ) {
        throw new BadRequestException(
          "The offer's end date must be on or after its start date.",
        );
      }
      throw error;
    }
  }
}
