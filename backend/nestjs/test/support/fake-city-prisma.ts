import { Prisma } from "@prisma/client";

/**
 * In-memory stand-in for the slice of Prisma used by city/store writes.
 * $transaction runs the callback against the same state and rolls the state
 * back if the callback throws, like a real database transaction.
 */
export type FakeStore = {
  id: string;
  name: string;
  category: string;
  city: string;
  cityId: string | null;
  governorateId: string;
  isActive: boolean;
  displayOrder: number;
  commissionRate: Prisma.Decimal;
  description: string;
  location: string;
  imageUrl: string | null;
  iconSeed: number;
  logoVersion: number;
  createdAt: Date;
};
export type FakeCity = {
  id: string;
  governorateId: string;
  nameAr: string;
  isActive: boolean;
  displayOrder: number;
  createdAt: Date;
  updatedAt: Date;
};

let seq = 0;
export const uuid = () =>
  `00000000-0000-4000-8000-${String(++seq).padStart(12, "0")}`;

export function makeStore(p: Partial<FakeStore>): FakeStore {
  return {
    id: uuid(),
    name: "متجر",
    category: "مطاعم",
    city: "",
    cityId: null,
    governorateId: "",
    isActive: true,
    displayOrder: 0,
    commissionRate: new Prisma.Decimal(5),
    description: "",
    location: "",
    imageUrl: null,
    iconSeed: 0,
    logoVersion: 0,
    createdAt: new Date(),
    ...p,
  };
}

export function makeCity(p: Partial<FakeCity>): FakeCity {
  return {
    id: uuid(),
    governorateId: "",
    nameAr: "",
    isActive: true,
    displayOrder: 0,
    createdAt: new Date(),
    updatedAt: new Date(),
    ...p,
  };
}

function matches(row: any, where: any = {}): boolean {
  return Object.entries(where).every(([k, v]: [string, any]) => {
    if (k === "id" && v && typeof v === "object" && "not" in v) {
      return row.id !== v.not;
    }
    if (v && typeof v === "object" && "equals" in v) {
      return String(row[k]).toLowerCase() === String(v.equals).toLowerCase();
    }
    if (v && typeof v === "object" && !(v instanceof Date)) return true;
    return row[k] === v;
  });
}

function sorted(rows: any[], orderBy: any[] = []) {
  return [...rows].sort((a, b) => {
    for (const o of orderBy) {
      const [k, dir] = Object.entries(o)[0] as [string, string];
      if (a[k] === b[k]) continue;
      const r = a[k] < b[k] ? -1 : 1;
      return dir === "desc" ? -r : r;
    }
    return 0;
  });
}

export function fakeCityPrisma(
  seed: { cities?: FakeCity[]; stores?: FakeStore[] } = {},
) {
  const state = {
    cities: [...(seed.cities ?? [])],
    stores: [...(seed.stores ?? [])],
    locks: [] as string[],
    merchantUpdates: [] as unknown[],
  };
  const api: any = {
    state,
    city: {
      findUnique: async ({ where }: any) =>
        state.cities.find((c) => c.id === where.id) ?? null,
      findFirst: async ({ where }: any) =>
        state.cities.find((c) => matches(c, where)) ?? null,
      findMany: async ({ where, orderBy }: any = {}) =>
        sorted(state.cities.filter((c) => matches(c, where)), orderBy),
      create: async ({ data }: any) => {
        const c = makeCity(data);
        state.cities.push(c);
        return c;
      },
      update: async ({ where, data }: any) => {
        const c = state.cities.find((x) => x.id === where.id)!;
        Object.assign(c, data);
        return c;
      },
    },
    store: {
      findUnique: async ({ where }: any) => {
        const s = state.stores.find((x) => x.id === where.id);
        return s ? { ...s } : null;
      },
      findFirst: async ({ where }: any) => {
        const s = state.stores.find((x) => matches(x, where));
        return s ? { ...s } : null;
      },
      findMany: async ({ where, orderBy }: any = {}) =>
        sorted(state.stores.filter((s) => matches(s, where)), orderBy).map(
          (s) => ({ ...s }),
        ),
      count: async ({ where }: any) =>
        state.stores.filter((s) => matches(s, where)).length,
      create: async ({ data }: any) => {
        const s = makeStore(data);
        state.stores.push(s);
        return { ...s };
      },
      update: async ({ where, data }: any) => {
        const s = state.stores.find((x) => x.id === where.id)!;
        Object.assign(s, data);
        return { ...s };
      },
      updateMany: async ({ where, data }: any) => {
        const rows = state.stores.filter((s) => matches(s, where));
        rows.forEach((s) => Object.assign(s, data));
        return { count: rows.length };
      },
    },
    merchantAccount: {
      updateMany: async (args: unknown) => {
        state.merchantUpdates.push(args);
        return { count: 1 };
      },
    },
    governorate: { findUnique: async () => ({ id: "g" }) },
    $queryRaw: async (_s: TemplateStringsArray, id: string) => {
      state.locks.push(id);
      return [];
    },
    $transaction: async (arg: any) => {
      if (typeof arg !== "function") return Promise.all(arg);
      const before = {
        cities: state.cities.map((c) => ({ ...c })),
        stores: state.stores.map((s) => ({ ...s })),
      };
      try {
        return await arg(api);
      } catch (e) {
        state.cities.splice(0, state.cities.length, ...before.cities);
        state.stores.splice(0, state.stores.length, ...before.stores);
        throw e;
      }
    },
  };
  return api;
}
