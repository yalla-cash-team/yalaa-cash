import {
  BadRequestException,
  ConflictException,
} from "@nestjs/common";
import { AdminService } from "../src/admin/admin.service";
import { CustomerService } from "../src/customer/customer.service";
import { StoresService } from "../src/stores/stores.service";
import {
  insertAtPosition,
  positionChanges,
} from "../src/admin/store-ordering";
import {
  fakeCityPrisma,
  makeCity,
  makeStore,
} from "./support/fake-city-prisma";

const IDLIB = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee";
const ALEPPO = "ffffffff-ffff-4fff-8fff-ffffffffffff";

function world() {
  const idlibCity = makeCity({ governorateId: IDLIB, nameAr: "إدلب" });
  const ariha = makeCity({ governorateId: IDLIB, nameAr: "أريحا" });
  const aleppoCity = makeCity({ governorateId: ALEPPO, nameAr: "حلب" });
  // Same city name in another governorate must stay a different city.
  const idlibNameInAleppo = makeCity({ governorateId: ALEPPO, nameAr: "إدلب" });
  const mk = (name: string, category: string, order: number, c = idlibCity) =>
    makeStore({
      name,
      category,
      city: c.nameAr,
      cityId: c.id,
      governorateId: c.governorateId,
      displayOrder: order,
    });
  const a = mk("A", "مطاعم", 1);
  const b = mk("B", "صيدليات", 2);
  const c = mk("C", "ملابس", 3);
  const prisma = fakeCityPrisma({
    cities: [idlibCity, ariha, aleppoCity, idlibNameInAleppo],
    stores: [a, b, c],
  });
  const admin = new AdminService(prisma as any, {} as any, {} as any);
  const order = (cityId: string) =>
    prisma.state.stores
      .filter((s: any) => s.cityId === cityId && s.isActive)
      .sort((x: any, y: any) => x.displayOrder - y.displayOrder)
      .map((s: any) => `${s.name}:${s.displayOrder}`);
  return { prisma, admin, idlibCity, ariha, aleppoCity, idlibNameInAleppo, a, b, c, order };
}

const base = (w: ReturnType<typeof world>, extra: object = {}) => ({
  name: "جديد",
  category: "مكتبات",
  commissionRate: 5,
  governorateId: IDLIB,
  cityId: w.idlibCity.id,
  ...extra,
});

describe("store ordering helpers", () => {
  it("inserts at a position, clamps, and defaults to the end", () => {
    expect(insertAtPosition(["a", "b", "c"], "x", 2)).toEqual(["a", "x", "b", "c"]);
    expect(insertAtPosition(["a", "b", "c"], "x")).toEqual(["a", "b", "c", "x"]);
    expect(insertAtPosition(["a", "b"], "x", 99)).toEqual(["a", "b", "x"]);
    expect(insertAtPosition(["a", "b"], "x", 0)).toEqual(["x", "a", "b"]);
    expect(insertAtPosition(["a", "x", "b"], "x", 3)).toEqual(["a", "b", "x"]);
  });

  it("reports only rows whose position changes", () => {
    const cur = new Map([["a", 1], ["b", 5]]);
    expect(positionChanges(["a", "b"], cur)).toEqual([{ id: "b", displayOrder: 2 }]);
  });
});

describe("createStore ordering", () => {
  it("defaults to the end of the city's list", async () => {
    const w = world();
    const created = await w.admin.createStore(base(w) as any);
    expect(created.displayOrder).toBe(4);
    expect(created.cityId).toBe(w.idlibCity.id);
    expect(created.city).toBe("إدلب");
  });

  it("inserting into an occupied position shifts the others down", async () => {
    const w = world();
    const created = await w.admin.createStore(base(w, { displayOrder: 2 }) as any);
    expect(created.displayOrder).toBe(2);
    expect(w.order(w.idlibCity.id)).toEqual(["A:1", "جديد:2", "B:3", "C:4"]);
  });

  it("position 1 puts the new store first; too-large goes last", async () => {
    const w = world();
    await w.admin.createStore(base(w, { name: "N1", category: "x1", displayOrder: 1 }) as any);
    await w.admin.createStore(base(w, { name: "N9", category: "x2", displayOrder: 50 }) as any);
    expect(w.order(w.idlibCity.id)).toEqual(["N1:1", "A:2", "B:3", "C:4", "N9:5"]);
  });

  it("does not touch the ordering of other cities", async () => {
    const w = world();
    const other = makeStore({
      name: "Z", category: "مطاعم", city: "أريحا", cityId: w.ariha.id,
      governorateId: IDLIB, displayOrder: 1,
    });
    w.prisma.state.stores.push(other);
    await w.admin.createStore(base(w, { displayOrder: 1 }) as any);
    expect(w.order(w.ariha.id)).toEqual(["Z:1"]);
  });

  it("keeps one active store per city and category", async () => {
    const w = world();
    await expect(
      w.admin.createStore(base(w, { category: "مطاعم" }) as any),
    ).rejects.toBeInstanceOf(ConflictException);
    // The same category in a different city is fine.
    await expect(
      w.admin.createStore(base(w, { category: "مطاعم", cityId: w.ariha.id }) as any),
    ).resolves.toBeDefined();
  });

  it("the same city name in another governorate does not collide", async () => {
    const w = world();
    await expect(
      w.admin.createStore(
        base(w, {
          category: "مطاعم",
          governorateId: ALEPPO,
          cityId: w.idlibNameInAleppo.id,
        }) as any,
      ),
    ).resolves.toBeDefined();
  });

  it("rejects a city that is not in the chosen governorate", async () => {
    const w = world();
    await expect(
      w.admin.createStore(base(w, { cityId: w.aleppoCity.id }) as any),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it("rejects an inactive city for an active store", async () => {
    const w = world();
    w.ariha.isActive = false;
    await expect(
      w.admin.createStore(base(w, { cityId: w.ariha.id }) as any),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it("locks the city row inside the transaction", async () => {
    const w = world();
    await w.admin.createStore(base(w) as any);
    expect(w.prisma.state.locks).toEqual([w.idlibCity.id]);
  });

  it("a failed create leaves the order untouched", async () => {
    const w = world();
    await expect(
      w.admin.createStore(base(w, { category: "مطاعم", displayOrder: 1 }) as any),
    ).rejects.toThrow();
    expect(w.order(w.idlibCity.id)).toEqual(["A:1", "B:2", "C:3"]);
  });

  it("an inactive new store takes no position", async () => {
    const w = world();
    const s = await w.admin.createStore(base(w, { isActive: false }) as any);
    expect(s.displayOrder).toBe(0);
    expect(w.order(w.idlibCity.id)).toEqual(["A:1", "B:2", "C:3"]);
  });
});

describe("updateStore ordering", () => {
  it("moving to an earlier position shifts the stores between", async () => {
    const w = world();
    const r = await w.admin.updateStore(w.c.id, { displayOrder: 1 } as any);
    expect(r.displayOrder).toBe(1);
    expect(w.order(w.idlibCity.id)).toEqual(["C:1", "A:2", "B:3"]);
  });

  it("moving to a later position closes the gap", async () => {
    const w = world();
    await w.admin.updateStore(w.a.id, { displayOrder: 3 } as any);
    expect(w.order(w.idlibCity.id)).toEqual(["B:1", "C:2", "A:3"]);
  });

  it("editing other fields keeps the position", async () => {
    const w = world();
    const r = await w.admin.updateStore(w.b.id, { name: "B2" } as any);
    expect(r.displayOrder).toBe(2);
    expect(w.order(w.idlibCity.id)).toEqual(["A:1", "B2:2", "C:3"]);
  });

  it("changing city compacts the old city and inserts in the new one", async () => {
    const w = world();
    const target = makeStore({
      name: "T", category: "مطاعم", city: "أريحا", cityId: w.ariha.id,
      governorateId: IDLIB, displayOrder: 1,
    });
    w.prisma.state.stores.push(target);
    const r = await w.admin.updateStore(w.b.id, {
      cityId: w.ariha.id,
      displayOrder: 1,
    } as any);
    expect(r.cityId).toBe(w.ariha.id);
    expect(r.city).toBe("أريحا");
    expect(w.order(w.idlibCity.id)).toEqual(["A:1", "C:2"]);
    expect(w.order(w.ariha.id)).toEqual(["B:1", "T:2"]);
    expect([...w.prisma.state.locks].sort()).toEqual(
      [w.idlibCity.id, w.ariha.id].sort(),
    );
  });

  it("moving without a position appends to the new city", async () => {
    const w = world();
    const r = await w.admin.updateStore(w.a.id, { cityId: w.ariha.id } as any);
    expect(r.displayOrder).toBe(1);
    expect(w.order(w.idlibCity.id)).toEqual(["B:1", "C:2"]);
  });

  it("a move into an occupied category slot is refused and changes nothing", async () => {
    const w = world();
    w.prisma.state.stores.push(
      makeStore({ name: "Q", category: "مطاعم", city: "أريحا", cityId: w.ariha.id, governorateId: IDLIB, displayOrder: 1 }),
    );
    await expect(
      w.admin.updateStore(w.a.id, { cityId: w.ariha.id } as any),
    ).rejects.toBeInstanceOf(ConflictException);
    expect(w.order(w.idlibCity.id)).toEqual(["A:1", "B:2", "C:3"]);
  });

  it("changing governorate requires a city of the new governorate", async () => {
    const w = world();
    await expect(
      w.admin.updateStore(w.a.id, { governorateId: ALEPPO } as any),
    ).rejects.toBeInstanceOf(BadRequestException);
    const ok = await w.admin.updateStore(w.a.id, {
      governorateId: ALEPPO,
      cityId: w.aleppoCity.id,
    } as any);
    expect(ok.governorateId).toBe(ALEPPO);
    expect(ok.cityId).toBe(w.aleppoCity.id);
  });

  it("deactivating closes the gap and zeroes the position", async () => {
    const w = world();
    const r = await w.admin.updateStore(w.a.id, { isActive: false } as any);
    expect(r.displayOrder).toBe(0);
    expect(w.order(w.idlibCity.id)).toEqual(["B:1", "C:2"]);
  });

  it("reactivating puts the store at the end (or where requested)", async () => {
    const w = world();
    await w.admin.updateStore(w.a.id, { isActive: false } as any);
    const r = await w.admin.updateStore(w.a.id, { isActive: true } as any);
    expect(r.displayOrder).toBe(3);
    const again = await w.admin.updateStore(w.a.id, { displayOrder: 1 } as any);
    expect(again.displayOrder).toBe(1);
    expect(w.order(w.idlibCity.id)).toEqual(["A:1", "B:2", "C:3"]);
  });

  it("preserves unrelated store data (logo version, image, commission)", async () => {
    const w = world();
    w.a.logoVersion = 4;
    w.a.imageUrl = "https://x/y.png";
    await w.admin.updateStore(w.a.id, { displayOrder: 2 } as any);
    const row = w.prisma.state.stores.find((s: any) => s.id === w.a.id);
    expect(row.logoVersion).toBe(4);
    expect(row.imageUrl).toBe("https://x/y.png");
    expect(Number(row.commissionRate)).toBe(5);
  });
});

describe("deleteStore ordering and city admin", () => {
  it("soft delete closes the gap in the city's order", async () => {
    const w = world();
    await w.admin.deleteStore(w.b.id);
    expect(w.order(w.idlibCity.id)).toEqual(["A:1", "C:2"]);
    expect(w.prisma.state.stores.find((s: any) => s.id === w.b.id).isActive).toBe(false);
  });

  it("renaming a city mirrors the name onto its stores", async () => {
    const w = world();
    await w.admin.updateCity(w.idlibCity.id, { nameAr: "إدلب المدينة" });
    expect(w.a.city).toBe("إدلب المدينة");
  });

  it("refuses duplicate city names inside one governorate only", async () => {
    const w = world();
    await expect(
      w.admin.createCity({ governorateId: IDLIB, nameAr: "أريحا" }),
    ).rejects.toBeInstanceOf(ConflictException);
    await expect(
      w.admin.createCity({ governorateId: ALEPPO, nameAr: "أريحا" }),
    ).resolves.toBeDefined();
  });

  it("refuses to deactivate a city that still has active stores", async () => {
    const w = world();
    await expect(
      w.admin.updateCity(w.idlibCity.id, { isActive: false }),
    ).rejects.toBeInstanceOf(ConflictException);
    await expect(
      w.admin.updateCity(w.ariha.id, { isActive: false }),
    ).resolves.toBeDefined();
  });
});

describe("customer city selection and filtering", () => {
  it("the public store query filters by city id and orders by position", async () => {
    const prisma: any = { store: { findMany: jest.fn().mockResolvedValue([]) } };
    await new StoresService(prisma).listActiveStores({
      governorateId: IDLIB,
      cityId: "city-1",
    } as any);
    const arg = prisma.store.findMany.mock.calls[0][0];
    expect(arg.where).toMatchObject({ isActive: true, governorateId: IDLIB, cityId: "city-1" });
    expect(arg.orderBy).toEqual([
      { city: "asc" },
      { displayOrder: "asc" },
      { name: "asc" },
      { id: "asc" },
    ]);
  });

  it("only active cities of active governorates are offered", async () => {
    const prisma: any = { city: { findMany: jest.fn().mockResolvedValue([]) } };
    await new CustomerService(prisma, {} as any, {} as any, {} as any).listActiveCities(IDLIB);
    expect(prisma.city.findMany.mock.calls[0][0].where).toEqual({
      isActive: true,
      governorate: { isActive: true },
      governorateId: IDLIB,
    });
  });

  it("a city outside the customer's governorate is rejected", async () => {
    const city = makeCity({ governorateId: ALEPPO, nameAr: "حلب" });
    const prisma: any = {
      customerProfile: {
        findUnique: jest.fn().mockResolvedValue({ governorateId: IDLIB }),
        update: jest.fn(),
      },
      city: { findFirst: jest.fn().mockResolvedValue(city) },
    };
    const svc = new CustomerService(prisma, {} as any, {} as any, {} as any);
    await expect(svc.updateCity("u1", { cityId: city.id })).rejects.toBeInstanceOf(
      BadRequestException,
    );
    expect(prisma.customerProfile.update).not.toHaveBeenCalled();
  });

  it("a valid city is saved on the profile", async () => {
    const city = makeCity({ governorateId: IDLIB, nameAr: "أريحا" });
    const prisma: any = {
      customerProfile: {
        findUnique: jest.fn().mockResolvedValue({ governorateId: IDLIB }),
        update: jest.fn().mockResolvedValue({
          userId: "u1", name: "n", governorate: "إدلب", governorateId: IDLIB,
          cityId: city.id, pointsBalance: BigInt(0), createdAt: new Date(),
          user: { phone: "1", authMethod: "PHONE" },
        }),
      },
      city: { findFirst: jest.fn().mockResolvedValue(city) },
    };
    const svc = new CustomerService(prisma, {} as any, {} as any, {} as any);
    const out = await svc.updateCity("u1", { cityId: city.id });
    expect(out.cityId).toBe(city.id);
    expect(prisma.customerProfile.update.mock.calls[0][0].data).toEqual({ cityId: city.id });
  });

  it("changing governorate clears the saved city", async () => {
    const prisma: any = {
      governorate: {
        findFirst: jest.fn().mockResolvedValue({ id: ALEPPO, nameAr: "حلب" }),
      },
      customerProfile: {
        update: jest.fn().mockResolvedValue({
          userId: "u1", name: "n", governorate: "حلب", governorateId: ALEPPO,
          cityId: null, pointsBalance: BigInt(0), createdAt: new Date(),
          user: { phone: "1", authMethod: "PHONE" },
        }),
      },
    };
    const svc = new CustomerService(prisma, {} as any, {} as any, {} as any);
    await svc.updateGovernorate("u1", { governorateId: ALEPPO });
    expect(prisma.customerProfile.update.mock.calls[0][0].data.cityId).toBeNull();
  });
});
