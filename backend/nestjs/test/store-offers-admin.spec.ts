import { BadRequestException, NotFoundException } from "@nestjs/common";
import { OffersService } from "../src/offers/offers.service";
import {
  createFakeOffersPrisma,
  fakeStore,
  FakeOffersPrisma,
  gifBytes,
  INACTIVE_STORE,
  jpegBytes,
  MISSING_ID,
  pngBytes,
  STORE_A,
  STORE_B,
  webpBytes,
} from "./support/fake-offers-prisma";

/**
 * Admin offer management (OffersService admin methods) against an in-memory
 * fake Prisma. Never touches a database.
 */

const NOW = new Date("2026-11-05T09:00:00.000Z"); // 12:00 in Damascus
const OFFER_1 = "11111111-1111-4111-8111-111111111111";
const OFFER_2 = "22222222-2222-4222-8222-222222222222";
const OFFER_B = "33333333-3333-4333-8333-333333333333";

function setup(seed: Parameters<typeof createFakeOffersPrisma>[0] = {}) {
  const prisma = createFakeOffersPrisma({
    stores: [
      fakeStore({ id: STORE_A }),
      fakeStore({ id: STORE_B, name: "Store B", category: "Cafe" }),
      fakeStore({ id: INACTIVE_STORE, name: "Closed", isActive: false }),
    ],
    ...seed,
  });
  const service = new OffersService(prisma as any);
  return { prisma, service };
}

function expectStoresUntouched(prisma: FakeOffersPrisma) {
  for (const method of ["create", "update", "updateMany", "delete", "deleteMany", "upsert"] as const) {
    expect(prisma.store[method]).not.toHaveBeenCalled();
  }
}

describe("OffersService.createOffer", () => {
  it("creates an offer with Damascus date boundaries and defaults", async () => {
    const { prisma, service } = setup();
    const offer = await service.createOffer(
      STORE_A,
      { title: "خصم الشتاء", startDate: "2026-11-01", endDate: "2026-11-30" },
      NOW,
    );

    expect(offer).toMatchObject({
      storeId: STORE_A,
      title: "خصم الشتاء",
      description: "",
      discountLabel: null,
      isActive: true,
      displayOrder: 0,
      startDate: "2026-11-01",
      endDate: "2026-11-30",
      startsAt: "2026-10-31T21:00:00.000Z",
      endsBefore: "2026-11-30T21:00:00.000Z",
      status: "active",
      hasImage: false,
      imageUrl: null,
      imageVersion: 0,
    });
    expect(prisma._offers.size).toBe(1);
    expectStoresUntouched(prisma);
  });

  it("stores optional fields and normalises a blank discount label to null", async () => {
    const { prisma, service } = setup();
    const offer = await service.createOffer(
      STORE_A,
      {
        title: "عرض",
        description: "تفاصيل",
        discountLabel: "خصم 20%",
        isActive: false,
        displayOrder: 3,
      },
      NOW,
    );
    expect(offer).toMatchObject({
      description: "تفاصيل",
      discountLabel: "خصم 20%",
      isActive: false,
      displayOrder: 3,
      status: "inactive",
      startDate: null,
      endDate: null,
    });

    const blank = await service.createOffer(STORE_A, { title: "عرض", discountLabel: "" }, NOW);
    expect(blank.discountLabel).toBeNull();
    expect(prisma._offers.size).toBe(2);
  });

  it("returns 404 for a missing store and writes nothing", async () => {
    const { prisma, service } = setup();
    await expect(service.createOffer(MISSING_ID, { title: "عرض" }, NOW)).rejects.toThrow(
      new NotFoundException("Store was not found."),
    );
    expect(prisma.storeOffer.create).not.toHaveBeenCalled();
  });

  it("rejects a reversed or impossible date range before any lookup or write", async () => {
    const { prisma, service } = setup();
    await expect(
      service.createOffer(
        STORE_A,
        { title: "عرض", startDate: "2026-11-10", endDate: "2026-11-09" },
        NOW,
      ),
    ).rejects.toThrow(BadRequestException);
    await expect(
      service.createOffer(STORE_A, { title: "عرض", endDate: "2026-02-30" }, NOW),
    ).rejects.toThrow(BadRequestException);
    expect(prisma.storeOffer.create).not.toHaveBeenCalled();
  });

  it("never changes the store's city, category, active flag or exclusivity", async () => {
    const { prisma, service } = setup();
    const before = { ...prisma._stores.get(STORE_A)! };
    await service.createOffer(STORE_A, { title: "عرض" }, NOW);
    expect(prisma._stores.get(STORE_A)).toEqual(before);
    expectStoresUntouched(prisma);
  });
});

describe("OffersService.listStoreOffersForAdmin", () => {
  it("keeps inactive, scheduled and expired offers, ordered by displayOrder then newest", async () => {
    const { service } = setup({
      offers: [
        { id: OFFER_1, storeId: STORE_A, title: "expired", displayOrder: 1,
          endsBefore: new Date("2026-11-01T21:00:00Z") },
        { id: OFFER_2, storeId: STORE_A, title: "inactive", displayOrder: 0, isActive: false },
        { id: "44444444-4444-4444-8444-444444444444", storeId: STORE_A, title: "scheduled",
          displayOrder: 0, startsAt: new Date("2026-12-01T21:00:00Z") },
        { id: OFFER_B, storeId: STORE_B, title: "other store" },
      ],
    });

    const list = await service.listStoreOffersForAdmin(STORE_A, NOW);
    expect(list.map((o) => [o.title, o.status])).toEqual([
      ["scheduled", "scheduled"], // order 0, newer
      ["inactive", "inactive"], // order 0, older
      ["expired", "expired"], // order 1
    ]);
  });

  it("lists offers of an inactive (soft-deleted) store for admins", async () => {
    const { service } = setup({
      offers: [{ id: OFFER_1, storeId: INACTIVE_STORE, title: "kept" }],
    });
    expect(await service.listStoreOffersForAdmin(INACTIVE_STORE, NOW)).toHaveLength(1);
  });

  it("returns an empty list for a store without offers and 404 for a missing store", async () => {
    const { service } = setup();
    expect(await service.listStoreOffersForAdmin(STORE_A, NOW)).toEqual([]);
    await expect(service.listStoreOffersForAdmin(MISSING_ID, NOW)).rejects.toThrow(
      NotFoundException,
    );
  });
});

describe("OffersService.updateOffer", () => {
  const seeded = () =>
    setup({
      offers: [
        {
          id: OFFER_1,
          storeId: STORE_A,
          title: "Original",
          description: "desc",
          discountLabel: "خصم 10%",
          displayOrder: 2,
          startsAt: new Date("2026-11-09T21:00:00.000Z"), // 2026-11-10
          endsBefore: new Date("2026-11-20T21:00:00.000Z"), // through 2026-11-20
        },
      ],
    });

  it("changes only the provided fields", async () => {
    const { prisma, service } = seeded();
    const updated = await service.updateOffer(OFFER_1, { title: "Renamed" }, NOW);
    expect(updated).toMatchObject({
      title: "Renamed",
      description: "desc",
      discountLabel: "خصم 10%",
      displayOrder: 2,
      startDate: "2026-11-10",
      endDate: "2026-11-20",
      storeId: STORE_A,
    });
    expect(prisma.storeOffer.update).toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: OFFER_1 }, data: { title: "Renamed" } }),
    );
  });

  it("deactivates and reactivates", async () => {
    const { service } = seeded();
    expect((await service.updateOffer(OFFER_1, { isActive: false }, NOW)).status).toBe(
      "inactive",
    );
    const back = await service.updateOffer(OFFER_1, { isActive: true }, NOW);
    expect(back.isActive).toBe(true);
    expect(back.status).toBe("scheduled"); // starts 2026-11-10
  });

  it("validates a partial date change against the stored other boundary", async () => {
    const { prisma, service } = seeded();
    await expect(
      service.updateOffer(OFFER_1, { endDate: "2026-11-09" }, NOW),
    ).rejects.toThrow("The offer's end date must be on or after its start date.");
    await expect(
      service.updateOffer(OFFER_1, { startDate: "2026-11-21" }, NOW),
    ).rejects.toThrow(BadRequestException);
    expect(prisma.storeOffer.update).not.toHaveBeenCalled();

    const moved = await service.updateOffer(OFFER_1, { endDate: "2026-11-10" }, NOW);
    expect([moved.startDate, moved.endDate]).toEqual(["2026-11-10", "2026-11-10"]);
  });

  it("clears optional fields with explicit null", async () => {
    const { service } = seeded();
    const cleared = await service.updateOffer(
      OFFER_1,
      { startDate: null, endDate: null, description: null, discountLabel: null },
      NOW,
    );
    expect(cleared).toMatchObject({
      startDate: null,
      endDate: null,
      startsAt: null,
      endsBefore: null,
      description: "",
      discountLabel: null,
      status: "active",
    });
  });

  it("treats an empty body as a no-op", async () => {
    const { prisma, service } = seeded();
    const same = await service.updateOffer(OFFER_1, {}, NOW);
    expect(same.title).toBe("Original");
    expect(prisma.storeOffer.update).not.toHaveBeenCalled();
  });

  it("returns 404 for a missing offer", async () => {
    const { service } = seeded();
    await expect(service.updateOffer(MISSING_ID, { title: "x y" }, NOW)).rejects.toThrow(
      new NotFoundException("Offer was not found."),
    );
  });

  it("maps a concurrent deletion (P2025) to 404", async () => {
    const { prisma, service } = seeded();
    prisma.storeOffer.update.mockImplementationOnce(async () => {
      prisma._offers.delete(OFFER_1);
      const { Prisma } = await import("@prisma/client");
      throw new Prisma.PrismaClientKnownRequestError("gone", {
        code: "P2025",
        clientVersion: "test",
      });
    });
    await expect(service.updateOffer(OFFER_1, { title: "Renamed" }, NOW)).rejects.toThrow(
      NotFoundException,
    );
  });

  it("maps a database window CHECK violation to 400", async () => {
    const { prisma, service } = seeded();
    prisma.storeOffer.update.mockRejectedValueOnce(
      new Error('violates check constraint "StoreOffer_window_check"'),
    );
    await expect(service.updateOffer(OFFER_1, { title: "Renamed" }, NOW)).rejects.toThrow(
      BadRequestException,
    );
  });

  it("never modifies the parent store", async () => {
    const { prisma, service } = seeded();
    await service.updateOffer(OFFER_1, { title: "Renamed", isActive: false }, NOW);
    expectStoresUntouched(prisma);
    const data = prisma.storeOffer.update.mock.calls[0][0].data;
    expect(Object.keys(data)).not.toEqual(expect.arrayContaining(["store", "storeId"]));
  });
});

describe("OffersService.deleteOffer", () => {
  it("deletes exactly the addressed offer and its image, nothing else", async () => {
    const { prisma, service } = setup({
      offers: [
        { id: OFFER_1, storeId: STORE_A },
        { id: OFFER_2, storeId: STORE_A },
        { id: OFFER_B, storeId: STORE_B },
      ],
      images: [
        { offerId: OFFER_1, contentType: "image/png", data: pngBytes(), updatedAt: NOW },
        { offerId: OFFER_2, contentType: "image/png", data: pngBytes(), updatedAt: NOW },
      ],
    });

    const result = await service.deleteOffer(OFFER_1);
    expect(result).toEqual({ id: OFFER_1, storeId: STORE_A, deleted: true });
    expect([...prisma._offers.keys()].sort()).toEqual([OFFER_2, OFFER_B].sort());
    expect([...prisma._images.keys()]).toEqual([OFFER_2]);
    expect(prisma.storeOffer.delete).toHaveBeenCalledWith({ where: { id: OFFER_1 } });
    expect(prisma.storeOffer.deleteMany).not.toHaveBeenCalled();
    expectStoresUntouched(prisma);
  });

  it("returns 404 for a missing offer and deletes nothing", async () => {
    const { prisma, service } = setup({ offers: [{ id: OFFER_1, storeId: STORE_A }] });
    await expect(service.deleteOffer(MISSING_ID)).rejects.toThrow(NotFoundException);
    expect(prisma.storeOffer.delete).not.toHaveBeenCalled();
    expect(prisma._offers.size).toBe(1);
  });
});

describe("OffersService offer images (admin)", () => {
  const seeded = () => setup({ offers: [{ id: OFFER_1, storeId: STORE_A }] });

  it.each([
    ["image/png", pngBytes()],
    ["image/jpeg", jpegBytes()],
    ["image/webp", webpBytes()],
  ])("stores a %s image and bumps imageVersion", async (type, bytes) => {
    const { prisma, service } = seeded();
    const offer = await service.setOfferImage(
      OFFER_1,
      { contentType: type, dataBase64: bytes.toString("base64") },
      NOW,
    );
    expect(offer).toMatchObject({
      hasImage: true,
      imageVersion: 1,
      imageUrl: `/admin/offers/${OFFER_1}/image?v=1`,
    });
    const stored = prisma._images.get(OFFER_1)!;
    expect(stored.contentType).toBe(type);
    expect(Buffer.from(stored.data).equals(bytes)).toBe(true);
  });

  it("bumps the version on every replacement and on removal", async () => {
    const { prisma, service } = seeded();
    const upload = (bytes: Buffer) =>
      service.setOfferImage(
        OFFER_1,
        { contentType: "image/png", dataBase64: bytes.toString("base64") },
        NOW,
      );
    expect((await upload(pngBytes(80))).imageVersion).toBe(1);
    expect((await upload(pngBytes(90))).imageVersion).toBe(2);

    const removed = await service.removeOfferImage(OFFER_1, NOW);
    expect(removed).toMatchObject({ hasImage: false, imageUrl: null, imageVersion: 3 });
    expect(prisma._images.has(OFFER_1)).toBe(false);
    expect(prisma.storeOfferImage.deleteMany).toHaveBeenCalledWith({
      where: { offerId: OFFER_1 },
    });
  });

  it.each([
    ["GIF", "image/gif", gifBytes().toString("base64")],
    ["SVG", "image/svg+xml", Buffer.from("<svg/>").toString("base64")],
    ["mismatched signature", "image/png", jpegBytes().toString("base64")],
    ["oversized", "image/png", pngBytes(300 * 1024 + 1).toString("base64")],
    ["invalid base64", "image/png", "not base64!"],
  ])("rejects a %s upload without writing anything", async (_label, type, data) => {
    const { prisma, service } = seeded();
    await expect(
      service.setOfferImage(OFFER_1, { contentType: type, dataBase64: data }, NOW),
    ).rejects.toThrow(BadRequestException);
    expect(prisma.storeOffer.findUnique).not.toHaveBeenCalled();
    expect(prisma.storeOffer.update).not.toHaveBeenCalled();
    expect(prisma._offers.get(OFFER_1)!.imageVersion).toBe(0);
  });

  it("returns 404 for image operations on a missing offer", async () => {
    const { service } = seeded();
    const png = { contentType: "image/png", dataBase64: pngBytes().toString("base64") };
    await expect(service.setOfferImage(MISSING_ID, png, NOW)).rejects.toThrow(
      NotFoundException,
    );
    await expect(service.removeOfferImage(MISSING_ID, NOW)).rejects.toThrow(
      NotFoundException,
    );
    await expect(service.getOfferImageForAdmin(OFFER_1)).rejects.toThrow(
      "Offer image was not found.",
    );
  });

  it("serves the admin preview of an inactive offer's image", async () => {
    const { service } = setup({
      offers: [{ id: OFFER_1, storeId: STORE_A, isActive: false, imageVersion: 1 }],
      images: [{ offerId: OFFER_1, contentType: "image/webp", data: webpBytes(), updatedAt: NOW }],
    });
    const image = await service.getOfferImageForAdmin(OFFER_1);
    expect(image.contentType).toBe("image/webp");
  });
});
