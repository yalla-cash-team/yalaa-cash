import { BadRequestException, ConflictException } from "@nestjs/common";
import { AdminService } from "../src/admin/admin.service";
import { auditStores } from "../src/admin/city-audit";
import { cityNameKey, normalizeCityName } from "../src/admin/city-names";
import { StoresService } from "../src/stores/stores.service";
import { fakeCityPrisma, makeCity, makeStore } from "./support/fake-city-prisma";

const IDLIB = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee";
const ALEPPO = "ffffffff-ffff-4fff-8fff-ffffffffffff";

function world() {
  const idlib = makeCity({ governorateId: IDLIB, nameAr: "إدلب" });
  const ariha = makeCity({ governorateId: IDLIB, nameAr: "أريحا" });
  const aleppo = makeCity({ governorateId: ALEPPO, nameAr: "حلب" });
  const mk = (name: string, category: string, order: number, c = idlib) =>
    makeStore({
      name,
      category,
      city: c.nameAr,
      cityId: c.id,
      governorateId: c.governorateId,
      displayOrder: order,
    });
  const a1 = mk("A1", "مطاعم", 1);
  const a2 = mk("A2", "صيدليات", 2);
  const a3 = mk("A3", "ملابس", 3);
  const r1 = mk("R1", "مطاعم", 1, ariha);
  const r2 = mk("R2", "صيدليات", 2, ariha);
  const prisma = fakeCityPrisma({
    cities: [idlib, ariha, aleppo],
    stores: [a1, a2, a3, r1, r2],
  });
  const admin = new AdminService(prisma as any, {} as any, {} as any);
  const order = (cityId: string) =>
    prisma.state.stores
      .filter((s: any) => s.cityId === cityId && s.isActive)
      .sort((x: any, y: any) => x.displayOrder - y.displayOrder)
      .map((s: any) => `${s.name}:${s.displayOrder}`);
  return { prisma, admin, idlib, ariha, aleppo, a1, a2, a3, r1, r2, order };
}

describe("city name keys", () => {
  it("collapse whitespace, case, diacritics and alef/yaa/taa-marbuta forms", () => {
    expect(normalizeCityName("  إدلب   المدينة ")).toBe("إدلب المدينة");
    expect(cityNameKey("أريحا")).toBe(cityNameKey("اريحا"));
    expect(cityNameKey("سراقب")).toBe(cityNameKey(" سراقِب "));
    expect(cityNameKey("المعرة")).toBe(cityNameKey("المعرّة"));
    expect(cityNameKey("حماة")).toBe(cityNameKey("حماه"));
    expect(cityNameKey("Idlib")).toBe(cityNameKey("idlib "));
    // Genuinely different names stay different.
    expect(cityNameKey("إدلب")).not.toBe(cityNameKey("أريحا"));
  });
});

describe("no accidental city creation", () => {
  it("legacy free text that matches no city is rejected and creates nothing", async () => {
    const w = world();
    const cities = w.prisma.state.cities.length;
    const stores = w.prisma.state.stores.length;
    await expect(
      w.admin.createStore({
        name: "X", category: "مكتبات", commissionRate: 5,
        governorateId: IDLIB, city: "سرمدا",
      } as any),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(w.prisma.state.cities.length).toBe(cities);
    expect(w.prisma.state.stores.length).toBe(stores);
  });

  it("legacy free text that is a spelling variant maps to the EXISTING city", async () => {
    const w = world();
    const out = await w.admin.createStore({
      name: "X", category: "مكتبات", commissionRate: 5,
      governorateId: IDLIB, city: " اريحا ",
    } as any);
    expect(out.cityId).toBe(w.ariha.id);
    expect(out.city).toBe("أريحا");
    expect(w.prisma.state.cities).toHaveLength(3);
  });

  it("legacy update with an unknown city text is rejected and the store is untouched", async () => {
    const w = world();
    await expect(
      w.admin.updateStore(w.a1.id, { city: "غلط إملائي" } as any),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(w.order(w.idlib.id)).toEqual(["A1:1", "A2:2", "A3:3"]);
  });

  it("explicit createCity trims, collapses spaces and refuses variants", async () => {
    const w = world();
    const ok = await w.admin.createCity({
      governorateId: IDLIB, nameAr: "  معرة   النعمان ",
    });
    expect(ok.nameAr).toBe("معرة النعمان");
    for (const variant of ["اريحا", "أَريحا", " أريحا ", "أريحا"]) {
      await expect(
        w.admin.createCity({ governorateId: IDLIB, nameAr: variant }),
      ).rejects.toBeInstanceOf(ConflictException);
    }
    // The same name in another governorate is a different city.
    await expect(
      w.admin.createCity({ governorateId: ALEPPO, nameAr: "أريحا" }),
    ).resolves.toBeDefined();
  });
});

describe("safe rename and deactivation", () => {
  it("renaming keeps stores linked (by id) and mirrors the text", async () => {
    const w = world();
    await w.admin.updateCity(w.ariha.id, { nameAr: " أريحا  الجديدة " });
    expect(w.r1.cityId).toBe(w.ariha.id);
    expect(w.r1.city).toBe("أريحا الجديدة");
    expect(w.order(w.ariha.id)).toEqual(["R1:1", "R2:2"]);
  });

  it("renaming to another city's name (or variant) is refused", async () => {
    const w = world();
    await expect(
      w.admin.updateCity(w.ariha.id, { nameAr: "ادلب" }),
    ).rejects.toBeInstanceOf(ConflictException);
    expect(w.ariha.nameAr).toBe("أريحا");
    expect(w.r1.city).toBe("أريحا");
  });

  it("renaming only the spelling of itself is allowed", async () => {
    const w = world();
    await expect(
      w.admin.updateCity(w.ariha.id, { nameAr: "اريحا" }),
    ).resolves.toBeDefined();
  });

  it("deactivation is refused while active stores remain, no store is orphaned", async () => {
    const w = world();
    await expect(
      w.admin.updateCity(w.ariha.id, { isActive: false }),
    ).rejects.toBeInstanceOf(ConflictException);
    expect(w.ariha.isActive).toBe(true);
    expect(w.order(w.ariha.id)).toEqual(["R1:1", "R2:2"]);
  });

  it("deactivation works after the stores are deactivated, and then no store can be (re)activated there", async () => {
    const w = world();
    await w.admin.updateStore(w.r1.id, { isActive: false } as any);
    await w.admin.updateStore(w.r2.id, { isActive: false } as any);
    await w.admin.updateCity(w.ariha.id, { isActive: false });
    await expect(
      w.admin.updateStore(w.r1.id, { isActive: true } as any),
    ).rejects.toBeInstanceOf(BadRequestException);
    await expect(
      w.admin.createStore({
        name: "N", category: "مكتبات", commissionRate: 5,
        governorateId: IDLIB, cityId: w.ariha.id,
      } as any),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it("moving the last active store out lets the city be deactivated", async () => {
    const w = world();
    await w.admin.updateStore(w.r1.id, { cityId: w.idlib.id, category: "كافيهات" } as any);
    await w.admin.updateStore(w.r2.id, { cityId: w.idlib.id, category: "حلويات" } as any);
    await expect(
      w.admin.updateCity(w.ariha.id, { isActive: false }),
    ).resolves.toBeDefined();
  });
});

describe("display order is independent per city", () => {
  it("inserting at an occupied position changes only that city", async () => {
    const w = world();
    await w.admin.createStore({
      name: "N", category: "مكتبات", commissionRate: 5,
      governorateId: IDLIB, cityId: w.idlib.id, displayOrder: 1,
    } as any);
    expect(w.order(w.idlib.id)).toEqual(["N:1", "A1:2", "A2:3", "A3:4"]);
    expect(w.order(w.ariha.id)).toEqual(["R1:1", "R2:2"]);
  });

  it("moving a store to an occupied slot of another city keeps both cities contiguous", async () => {
    const w = world();
    await w.admin.updateStore(w.a2.id, {
      cityId: w.ariha.id, category: "حلويات", displayOrder: 2,
    } as any);
    expect(w.order(w.idlib.id)).toEqual(["A1:1", "A3:2"]);
    expect(w.order(w.ariha.id)).toEqual(["R1:1", "A2:2", "R2:3"]);
  });

  it("moving within a city never touches the other city's numbers", async () => {
    const w = world();
    await w.admin.updateStore(w.a3.id, { displayOrder: 1 } as any);
    expect(w.order(w.idlib.id)).toEqual(["A3:1", "A1:2", "A2:3"]);
    expect(w.order(w.ariha.id)).toEqual(["R1:1", "R2:2"]);
  });

  it("a refused move (exclusivity) leaves both cities exactly as before", async () => {
    const w = world();
    // Ariha already has an active "مطاعم" store (R1).
    await expect(
      w.admin.updateStore(w.a1.id, { cityId: w.ariha.id, displayOrder: 1 } as any),
    ).rejects.toBeInstanceOf(ConflictException);
    expect(w.order(w.idlib.id)).toEqual(["A1:1", "A2:2", "A3:3"]);
    expect(w.order(w.ariha.id)).toEqual(["R1:1", "R2:2"]);
  });

  it("exclusivity is per city: same category in two cities is fine, same city is not", async () => {
    const w = world();
    await expect(
      w.admin.createStore({
        name: "N", category: "مطاعم", commissionRate: 5,
        governorateId: ALEPPO, cityId: w.aleppo.id,
      } as any),
    ).resolves.toBeDefined();
    await expect(
      w.admin.createStore({
        name: "N2", category: "مطاعم", commissionRate: 5,
        governorateId: IDLIB, cityId: w.idlib.id,
      } as any),
    ).rejects.toBeInstanceOf(ConflictException);
  });
});

describe("GET /stores compatibility", () => {
  const stores = () => {
    const w = world();
    // A legacy store whose city could not be matched: no cityId.
    const orphan = makeStore({
      name: "Orphan", category: "x", city: "", cityId: null,
      governorateId: IDLIB, displayOrder: 0,
    });
    const inactive = makeStore({
      name: "Off", category: "y", city: "إدلب", cityId: w.idlib.id,
      governorateId: IDLIB, isActive: false,
    });
    w.prisma.state.stores.push(orphan, inactive);
    return { w, svc: new StoresService(w.prisma as any) };
  };

  it("old apps (no cityId) still get every active store of the governorate", async () => {
    const { svc } = stores();
    const out = await svc.listActiveStores({ governorateId: IDLIB } as any);
    expect(out.items.map((s: any) => s.name).sort()).toEqual(
      ["A1", "A2", "A3", "Orphan", "R1", "R2"].sort(),
    );
    expect(out.items.every((s: any) => s.isActive !== false)).toBe(true);
    // The response keeps every field old apps read.
    expect(out.items[0]).toEqual(
      expect.objectContaining({
        id: expect.any(String), name: expect.any(String), city: expect.any(String),
        governorateId: IDLIB, logoUrl: null,
      }),
    );
  });

  it("with no filters at all it still lists active stores", async () => {
    const { svc } = stores();
    const out = await svc.listActiveStores({} as any);
    expect(out.items.length).toBe(6);
  });

  it("new apps filter strictly by city and in display order", async () => {
    const { w, svc } = stores();
    const idlib = await svc.listActiveStores({ governorateId: IDLIB, cityId: w.idlib.id } as any);
    expect(idlib.items.map((s: any) => s.name)).toEqual(["A1", "A2", "A3"]);
    const ariha = await svc.listActiveStores({ governorateId: IDLIB, cityId: w.ariha.id } as any);
    expect(ariha.items.map((s: any) => s.name)).toEqual(["R1", "R2"]);
    expect(idlib.items.map((s: any) => s.displayOrder)).toEqual([1, 2, 3]);
  });

  it("a city filter never shows a store without cityId or an inactive one", async () => {
    const { w, svc } = stores();
    const out = await svc.listActiveStores({ cityId: w.idlib.id } as any);
    expect(out.items.map((s: any) => s.name)).not.toContain("Orphan");
    expect(out.items.map((s: any) => s.name)).not.toContain("Off");
  });
});

describe("pre-release audit", () => {
  const base = (over: object) => ({
    id: Math.random().toString(36).slice(2),
    name: "S", category: "c", city: "إدلب", governorateId: IDLIB,
    isActive: true, ...over,
  });
  const codes = (r: ReturnType<typeof auditStores>) => r.findings.map((f) => f.code);

  it("pre-migration: flags blank cities and spelling variants without changing data", () => {
    const stores = [
      base({ name: "A", city: "إدلب", category: "1" }),
      base({ name: "B", city: "ادلب", category: "2" }),
      base({ name: "C", city: "   ", category: "3" }),
      base({ name: "D", city: "Idlib", category: "4" }),
      base({ name: "E", city: "إدلب", governorateId: ALEPPO, category: "1" }),
    ];
    const copy = JSON.parse(JSON.stringify(stores));
    const r = auditStores(stores as any, [], false);
    expect(r.mode).toBe("pre-migration");
    expect(codes(r)).toEqual(
      expect.arrayContaining(["STORE_WITHOUT_CITY", "CITY_SPELLING_VARIANTS"]),
    );
    const variant = r.findings.find((f) => f.code === "CITY_SPELLING_VARIANTS")!;
    expect(variant.severity).toBe("manual");
    expect(variant.details!.names).toEqual(["إدلب", "ادلب"]);
    expect(r.releaseSafe).toBe(false); // active store C has no city
    expect(stores).toEqual(copy);
  });

  it("pre-migration: two active stores of one category in one city are a blocker", () => {
    const r = auditStores(
      [base({ name: "A" }), base({ name: "B", city: " إدلب " })] as any,
      [],
      false,
    );
    expect(codes(r)).toContain("EXCLUSIVITY_CONFLICT");
  });

  it("post-migration: clean data is release-safe", () => {
    const city = { id: "c1", governorateId: IDLIB, nameAr: "إدلب", isActive: true };
    const r = auditStores(
      [
        base({ cityId: "c1", displayOrder: 1, category: "1" }),
        base({ cityId: "c1", displayOrder: 2, category: "2" }),
      ] as any,
      [city],
      true,
    );
    expect(r.findings).toEqual([]);
    expect(r.releaseSafe).toBe(true);
  });

  it("post-migration: missing cityId, wrong governorate, inactive city, bad order", () => {
    const cities = [
      { id: "c1", governorateId: IDLIB, nameAr: "إدلب", isActive: true },
      { id: "c2", governorateId: ALEPPO, nameAr: "حلب", isActive: false },
    ];
    const r = auditStores(
      [
        base({ name: "NoCity", cityId: null }),
        base({ name: "Wrong", cityId: "c2", city: "حلب", category: "w" }),
        base({ name: "P1", cityId: "c1", displayOrder: 1, category: "p1" }),
        base({ name: "P3", cityId: "c1", displayOrder: 3, category: "p3" }),
      ] as any,
      cities,
      true,
    );
    expect(codes(r)).toEqual(
      expect.arrayContaining([
        "STORE_WITHOUT_CITY",
        "CITY_GOVERNORATE_MISMATCH",
        "ACTIVE_STORE_IN_INACTIVE_CITY",
        "DISPLAY_ORDER_INVALID",
      ]),
    );
    expect(r.releaseSafe).toBe(false);
  });

  it("an inactive store without a city is only a warning", () => {
    const r = auditStores(
      [base({ cityId: null, isActive: false })] as any,
      [{ id: "c1", governorateId: IDLIB, nameAr: "إدلب", isActive: true }],
      true,
    );
    expect(r.findings[0].severity).toBe("warning");
    expect(r.releaseSafe).toBe(true);
  });

  it("post-migration: cities with spelling variants are reported for manual merge only", () => {
    const cities = [
      { id: "c1", governorateId: IDLIB, nameAr: "إدلب", isActive: true },
      { id: "c2", governorateId: IDLIB, nameAr: "ادلب", isActive: true },
    ];
    const r = auditStores(
      [
        base({ cityId: "c1", displayOrder: 1, category: "1" }),
        base({ cityId: "c2", city: "ادلب", displayOrder: 1, category: "2" }),
      ] as any,
      cities,
      true,
    );
    const f = r.findings.find((x) => x.code === "CITY_SPELLING_VARIANTS")!;
    expect(f.severity).toBe("manual");
    expect(f.storeIds).toHaveLength(2);
    expect(r.releaseSafe).toBe(true); // no auto-merge, nothing blocks
  });
});
