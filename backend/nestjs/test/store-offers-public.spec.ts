import { NotFoundException } from "@nestjs/common";
import { OffersService, publiclyVisibleOfferWhere } from "../src/offers/offers.service";
import {
  createFakeOffersPrisma,
  fakeStore,
  INACTIVE_STORE,
  MISSING_ID,
  pngBytes,
  STORE_A,
  STORE_B,
} from "./support/fake-offers-prisma";

/**
 * Customer-facing offers: only active offers of active stores, inside their
 * Damascus validity window, ordered by displayOrder then newest.
 */

const NOW = new Date("2026-11-05T09:00:00.000Z"); // 2026-11-05 12:00 Damascus
const id = (n: number) => `${String(n).repeat(8)}-${String(n).repeat(4)}-4${String(n).repeat(3)}-8${String(n).repeat(3)}-${String(n).repeat(12)}`;

// Damascus day boundaries around NOW.
const TODAY_START = new Date("2026-11-04T21:00:00.000Z");
const TOMORROW_START = new Date("2026-11-05T21:00:00.000Z");

type Seed = NonNullable<Parameters<typeof createFakeOffersPrisma>[0]>;

function setup(offers: Seed["offers"], images: Seed["images"] = []) {
  const prisma = createFakeOffersPrisma({
    stores: [
      fakeStore({ id: STORE_A }),
      fakeStore({ id: STORE_B }),
      fakeStore({ id: INACTIVE_STORE, isActive: false }),
    ],
    offers,
    images,
  });
  return { prisma, service: new OffersService(prisma as any) };
}

describe("OffersService.listPublicStoreOffers", () => {
  it("returns only active offers inside their window", async () => {
    const { service } = setup([
      { id: id(1), storeId: STORE_A, title: "open-ended" },
      { id: id(2), storeId: STORE_A, title: "inactive", isActive: false },
      { id: id(3), storeId: STORE_A, title: "scheduled", startsAt: TOMORROW_START },
      { id: id(4), storeId: STORE_A, title: "expired", endsBefore: TODAY_START },
      { id: id(5), storeId: STORE_A, title: "starts today", startsAt: TODAY_START },
      { id: id(6), storeId: STORE_A, title: "last day today", endsBefore: TOMORROW_START },
      { id: id(7), storeId: STORE_B, title: "other store" },
    ]);
    const titles = (await service.listPublicStoreOffers(STORE_A, NOW)).map((o) => o.title);
    expect(titles.sort()).toEqual(["last day today", "open-ended", "starts today"]);
  });

  it("applies the window boundaries exactly (inclusive start, exclusive end)", async () => {
    const offers = [
      { id: id(1), storeId: STORE_A, title: "today only", startsAt: TODAY_START, endsBefore: TOMORROW_START },
    ];
    const { service } = setup(offers);
    const at = (iso: string) => service.listPublicStoreOffers(STORE_A, new Date(iso));
    expect(await at("2026-11-04T20:59:59.999Z")).toHaveLength(0); // 23:59:59.999 the day before
    expect(await at("2026-11-04T21:00:00.000Z")).toHaveLength(1); // 00:00 Damascus
    expect(await at("2026-11-05T20:59:59.999Z")).toHaveLength(1); // 23:59:59.999 Damascus
    expect(await at("2026-11-05T21:00:00.000Z")).toHaveLength(0); // next day 00:00
  });

  it("orders by displayOrder, then newest first", async () => {
    const { service } = setup([
      { id: id(1), storeId: STORE_A, title: "order1-old", displayOrder: 1, createdAt: new Date("2026-10-01T00:00:00Z") },
      { id: id(2), storeId: STORE_A, title: "order0-old", displayOrder: 0, createdAt: new Date("2026-10-01T00:00:00Z") },
      { id: id(3), storeId: STORE_A, title: "order1-new", displayOrder: 1, createdAt: new Date("2026-10-03T00:00:00Z") },
      { id: id(4), storeId: STORE_A, title: "order0-new", displayOrder: 0, createdAt: new Date("2026-10-02T00:00:00Z") },
    ]);
    const titles = (await service.listPublicStoreOffers(STORE_A, NOW)).map((o) => o.title);
    expect(titles).toEqual(["order0-new", "order0-old", "order1-new", "order1-old"]);
  });

  it("returns a clean public shape without image bytes or admin fields", async () => {
    const { service } = setup(
      [
        {
          id: id(1),
          storeId: STORE_A,
          title: "عرض",
          description: "تفاصيل",
          discountLabel: "خصم 20%",
          imageVersion: 2,
          startsAt: TODAY_START,
          endsBefore: TOMORROW_START,
        },
      ],
      [{ offerId: id(1), contentType: "image/png", data: pngBytes(), updatedAt: NOW }] as any,
    );
    const [offer] = await service.listPublicStoreOffers(STORE_A, NOW);
    expect(offer).toEqual({
      id: id(1),
      storeId: STORE_A,
      title: "عرض",
      description: "تفاصيل",
      discountLabel: "خصم 20%",
      imageUrl: `/offers/${id(1)}/image?v=2`,
      startDate: "2026-11-05",
      endDate: "2026-11-05",
      startsAt: "2026-11-04T21:00:00.000Z",
      endsBefore: "2026-11-05T21:00:00.000Z",
    });
    expect(JSON.stringify(offer)).not.toMatch(/data|contentType|isActive|displayOrder/);
  });

  it("gives a null imageUrl when the offer has no image", async () => {
    const { service } = setup([{ id: id(1), storeId: STORE_A, imageVersion: 3 }]);
    const [offer] = await service.listPublicStoreOffers(STORE_A, NOW);
    expect(offer.imageUrl).toBeNull();
  });

  it("returns an empty list for an active store with no valid offers", async () => {
    const { service } = setup([
      { id: id(1), storeId: STORE_A, isActive: false },
      { id: id(2), storeId: STORE_A, endsBefore: TODAY_START },
    ]);
    expect(await service.listPublicStoreOffers(STORE_A, NOW)).toEqual([]);
  });

  it("returns 404 for an inactive (soft-deleted) or missing store, even with active offers", async () => {
    const { prisma, service } = setup([{ id: id(1), storeId: INACTIVE_STORE }]);
    await expect(service.listPublicStoreOffers(INACTIVE_STORE, NOW)).rejects.toThrow(
      new NotFoundException("Store was not found."),
    );
    await expect(service.listPublicStoreOffers(MISSING_ID, NOW)).rejects.toThrow(
      NotFoundException,
    );
    expect(prisma.storeOffer.findMany).not.toHaveBeenCalled();
  });

  it("filters on the parent store's active flag inside the offer query too", () => {
    expect(publiclyVisibleOfferWhere(NOW)).toEqual({
      isActive: true,
      store: { isActive: true },
      AND: [
        { OR: [{ startsAt: null }, { startsAt: { lte: NOW } }] },
        { OR: [{ endsBefore: null }, { endsBefore: { gt: NOW } }] },
      ],
    });
  });
});

describe("OffersService.getPublicOfferImage", () => {
  const image = (offerId: string) => ({
    offerId,
    contentType: "image/png",
    data: pngBytes(),
    updatedAt: NOW,
  });

  it("serves the image of a visible offer", async () => {
    const { service } = setup([{ id: id(1), storeId: STORE_A, imageVersion: 1 }], [image(id(1))] as any);
    const result = await service.getPublicOfferImage(id(1), NOW);
    expect(result.contentType).toBe("image/png");
    expect(Buffer.from(result.data).equals(pngBytes())).toBe(true);
  });

  it.each([
    ["an inactive offer", { isActive: false }, STORE_A],
    ["a scheduled offer", { startsAt: TOMORROW_START }, STORE_A],
    ["an expired offer", { endsBefore: TODAY_START }, STORE_A],
    ["an inactive store", {}, INACTIVE_STORE],
  ])("does not serve the image of %s", async (_label, fields, storeId) => {
    const { service } = setup([{ id: id(1), storeId, ...fields }], [image(id(1))] as any);
    await expect(service.getPublicOfferImage(id(1), NOW)).rejects.toThrow(
      new NotFoundException("Offer image was not found."),
    );
  });

  it("returns 404 when a visible offer has no image or the offer is missing", async () => {
    const { service } = setup([{ id: id(1), storeId: STORE_A }]);
    await expect(service.getPublicOfferImage(id(1), NOW)).rejects.toThrow(NotFoundException);
    await expect(service.getPublicOfferImage(MISSING_ID, NOW)).rejects.toThrow(
      NotFoundException,
    );
  });
});
