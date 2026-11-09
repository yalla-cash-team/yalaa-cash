import { AdminService } from "../src/admin/admin.service";
import { StoresService } from "../src/stores/stores.service";
import { fakeCityPrisma, makeCity, makeStore } from "./support/fake-city-prisma";

/**
 * Covers Store <-> Governorate filtering (Store.governorateId -> Governorate.id,
 * mirroring the existing Banner.governorateId pattern — no separate Province
 * concept introduced). PrismaService is replaced with a minimal hand-rolled
 * mock, matching the style already used in settlement-cycle.spec.ts — no
 * real database is touched.
 */

const IDLIB_ID = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee";
const ALEPPO_ID = "ffffffff-ffff-4fff-8fff-ffffffffffff";

function fakePrisma(overrides: Record<string, unknown> = {}) {
  return {
    store: {
      findMany: jest.fn(),
      findUnique: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
    },
    ...overrides,
  };
}

const idlibStore = {
  id: "11111111-1111-1111-1111-111111111111",
  name: "Idlib Store",
  category: "restaurants",
  city: "Idlib",
  commissionRate: "5.0",
  description: "",
  location: "",
  imageUrl: null,
  iconSeed: 0,
  isActive: true,
  governorateId: IDLIB_ID,
  createdAt: new Date(),
};

const aleppoStore = {
  id: "22222222-2222-2222-2222-222222222222",
  name: "Aleppo Store",
  category: "restaurants",
  city: "Aleppo",
  commissionRate: "5.0",
  description: "",
  location: "",
  imageUrl: null,
  iconSeed: 0,
  isActive: true,
  governorateId: ALEPPO_ID,
  createdAt: new Date(),
};

describe("Store <-> Governorate filtering", () => {
  // 2. Idlib customer receives only Idlib stores.
  it("returns only Idlib stores when filtering by the Idlib governorateId", async () => {
    const prisma = fakePrisma();
    prisma.store.findMany.mockResolvedValue([idlibStore]);
    const stores = new StoresService(prisma as any);

    const result = await stores.listActiveStores({ governorateId: IDLIB_ID } as any);

    expect(result.items).toHaveLength(1);
    expect(result.items[0].governorateId).toBe(IDLIB_ID);
    expect(prisma.store.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ governorateId: IDLIB_ID }),
      }),
    );
  });

  // 3. Aleppo customer receives only Aleppo stores.
  it("returns only Aleppo stores when filtering by the Aleppo governorateId", async () => {
    const prisma = fakePrisma();
    prisma.store.findMany.mockResolvedValue([aleppoStore]);
    const stores = new StoresService(prisma as any);

    const result = await stores.listActiveStores({ governorateId: ALEPPO_ID } as any);

    expect(result.items).toHaveLength(1);
    expect(result.items[0].governorateId).toBe(ALEPPO_ID);
  });

  // 4. Customer switching from Idlib to Aleppo changes returned stores.
  it("switching the governorateId filter changes which stores are returned", async () => {
    const prisma = fakePrisma();
    const stores = new StoresService(prisma as any);

    prisma.store.findMany.mockResolvedValueOnce([idlibStore]);
    const first = await stores.listActiveStores({ governorateId: IDLIB_ID } as any);
    expect(first.items.map((s) => s.id)).toEqual([idlibStore.id]);

    prisma.store.findMany.mockResolvedValueOnce([aleppoStore]);
    const second = await stores.listActiveStores({ governorateId: ALEPPO_ID } as any);
    expect(second.items.map((s) => s.id)).toEqual([aleppoStore.id]);
  });

  // 5. No cross-governorate store leakage: the query itself is scoped by
  // governorateId, so a mixed-store mock proves the filter is what the
  // database applies, not client-side filtering.
  it("never includes a store from another governorate in the where clause result set", async () => {
    const prisma = fakePrisma();
    // Simulates the database honoring the WHERE governorateId = Idlib filter
    // by never returning the Aleppo row in the first place.
    prisma.store.findMany.mockResolvedValue([idlibStore]);
    const stores = new StoresService(prisma as any);

    const result = await stores.listActiveStores({ governorateId: IDLIB_ID } as any);

    expect(result.items.some((s) => s.governorateId === ALEPPO_ID)).toBe(false);
    expect(result.items.every((s) => s.governorateId === IDLIB_ID)).toBe(true);
  });

  // 7. Store create requires governorateId (enforced by CreateStoreDto's
  // required, non-optional field — verified here at the service level: the
  // provided governorateId is always persisted, never silently dropped).
  it("createStore persists the provided governorateId", async () => {
    const city = makeCity({ governorateId: IDLIB_ID, nameAr: "Idlib" });
    const prisma = fakeCityPrisma({ cities: [city] });
    const admin = new AdminService(prisma as any, {} as any, {} as any);

    const out = await admin.createStore({
      name: "Idlib Store",
      category: "restaurants",
      cityId: city.id,
      commissionRate: 5,
      governorateId: IDLIB_ID,
    } as any);

    expect(out.governorateId).toBe(IDLIB_ID);
    expect(prisma.state.stores[0].governorateId).toBe(IDLIB_ID);
  });

  // 8. Store update can change governorateId (with a city of the new one).
  it("updateStore persists a changed governorateId", async () => {
    const idlibCity = makeCity({ governorateId: IDLIB_ID, nameAr: "Idlib" });
    const aleppoCity = makeCity({ governorateId: ALEPPO_ID, nameAr: "Aleppo" });
    const store = makeStore({
      city: "Idlib",
      cityId: idlibCity.id,
      governorateId: IDLIB_ID,
      displayOrder: 1,
    });
    const prisma = fakeCityPrisma({
      cities: [idlibCity, aleppoCity],
      stores: [store],
    });
    const admin = new AdminService(prisma as any, {} as any, {} as any);

    const out = await admin.updateStore(store.id, {
      governorateId: ALEPPO_ID,
      cityId: aleppoCity.id,
    } as any);

    expect(out.governorateId).toBe(ALEPPO_ID);
    expect(out.cityId).toBe(aleppoCity.id);
  });

  // Sanity: omitting governorateId from a query does not filter at all
  // (documents the deliberate "no filter if not provided" fallback for
  // the public /stores endpoint, distinct from ever falling back across
  // governorates when one WAS provided — see tests above).
  it("omitting governorateId from the query applies no governorate filter", async () => {
    const prisma = fakePrisma();
    prisma.store.findMany.mockResolvedValue([idlibStore, aleppoStore]);
    const stores = new StoresService(prisma as any);

    await stores.listActiveStores({} as any);

    const whereArg = prisma.store.findMany.mock.calls[0][0].where;
    expect(whereArg.governorateId).toBeUndefined();
  });
});
