import { Prisma } from "@prisma/client";
import { randomUUID } from "crypto";

/**
 * In-memory stand-in for the Prisma calls OffersService makes. It evaluates
 * the real `where` / `orderBy` / `include` / `select` arguments (the subset
 * the offers code uses), so filtering, ordering and visibility are tested
 * behaviourally, not just by inspecting call arguments. No database is ever
 * contacted.
 *
 * It also mirrors the migration's constraints: the StoreOffer_window_check
 * CHECK, the StoreOffer -> Store foreign key and the image cascade.
 */

export interface FakeStore {
  id: string;
  name: string;
  city: string;
  category: string;
  isActive: boolean;
  logoVersion: number;
}

export interface FakeOffer {
  id: string;
  storeId: string;
  title: string;
  description: string;
  discountLabel: string | null;
  imageVersion: number;
  startsAt: Date | null;
  endsBefore: Date | null;
  isActive: boolean;
  displayOrder: number;
  createdAt: Date;
  updatedAt: Date;
}

export interface FakeOfferImage {
  offerId: string;
  contentType: string;
  data: Uint8Array;
  updatedAt: Date;
}

type Row = Record<string, unknown>;
type Where = Record<string, unknown>;

export const STORE_A = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
export const STORE_B = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
export const INACTIVE_STORE = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
export const MISSING_ID = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";

export function fakeStore(overrides: Partial<FakeStore> = {}): FakeStore {
  return {
    id: STORE_A,
    name: "Store A",
    city: "Damascus",
    category: "Restaurant",
    isActive: true,
    logoVersion: 0,
    ...overrides,
  };
}

function compare(value: unknown, condition: unknown): boolean {
  if (condition === null) return value === null || value === undefined;
  if (condition instanceof Date) {
    return value instanceof Date && value.getTime() === condition.getTime();
  }
  if (typeof condition !== "object") return value === condition;

  const ops = condition as Record<string, unknown>;
  for (const [op, operand] of Object.entries(ops)) {
    if (value === null || value === undefined) return false;
    const a = value instanceof Date ? value.getTime() : (value as number);
    const b = operand instanceof Date ? operand.getTime() : (operand as number);
    switch (op) {
      case "equals":
        if (a !== b) return false;
        break;
      case "lt":
        if (!(a < b)) return false;
        break;
      case "lte":
        if (!(a <= b)) return false;
        break;
      case "gt":
        if (!(a > b)) return false;
        break;
      case "gte":
        if (!(a >= b)) return false;
        break;
      default:
        throw new Error(`fake prisma: unsupported operator ${op}`);
    }
  }
  return true;
}

function constraintError(): Error {
  return new Error(
    'new row for relation "StoreOffer" violates check constraint "StoreOffer_window_check"',
  );
}

function notFound(): Error {
  return new Prisma.PrismaClientKnownRequestError("Record to update not found.", {
    code: "P2025",
    clientVersion: "test",
  });
}

export function createFakeOffersPrisma(
  seed: {
    stores?: FakeStore[];
    offers?: Array<Partial<FakeOffer> & { id: string; storeId: string }>;
    images?: FakeOfferImage[];
  } = {},
) {
  const stores = new Map<string, FakeStore>();
  const offers = new Map<string, FakeOffer>();
  const images = new Map<string, FakeOfferImage>();
  // Strictly increasing creation times so "newest first" is deterministic.
  let tick = Date.UTC(2026, 0, 1);
  const nextTime = () => new Date((tick += 1000));

  for (const store of seed.stores ?? [fakeStore()]) stores.set(store.id, { ...store });
  for (const offer of seed.offers ?? []) {
    const created = offer.createdAt ?? nextTime();
    offers.set(offer.id, {
      title: "Offer",
      description: "",
      discountLabel: null,
      imageVersion: 0,
      startsAt: null,
      endsBefore: null,
      isActive: true,
      displayOrder: 0,
      updatedAt: created,
      ...offer,
      createdAt: created,
    });
  }
  for (const image of seed.images ?? []) images.set(image.offerId, { ...image });

  function matches(row: Row, where: Where | undefined): boolean {
    if (!where) return true;
    for (const [key, condition] of Object.entries(where)) {
      if (key === "AND") {
        if (!(condition as Where[]).every((w) => matches(row, w))) return false;
      } else if (key === "OR") {
        if (!(condition as Where[]).some((w) => matches(row, w))) return false;
      } else if (key === "store") {
        const store = stores.get(row.storeId as string);
        if (!store || !matches(store as unknown as Row, condition as Where)) return false;
      } else if (!compare(row[key], condition)) {
        return false;
      }
    }
    return true;
  }

  function project(offer: FakeOffer, args: { include?: any; select?: any }): Row {
    const image = images.get(offer.id) ?? null;
    const pickImage = (selection: Record<string, boolean>) =>
      image
        ? Object.fromEntries(
            Object.keys(selection).map((k) => [k, (image as unknown as Row)[k]]),
          )
        : null;
    if (args.select) {
      const out: Row = {};
      for (const key of Object.keys(args.select)) {
        out[key] =
          key === "image"
            ? pickImage(args.select.image.select)
            : (offer as unknown as Row)[key];
      }
      return out;
    }
    const out: Row = { ...offer };
    if (args.include?.image) out.image = pickImage(args.include.image.select);
    return out;
  }

  function sort(rows: FakeOffer[], orderBy: Array<Record<string, "asc" | "desc">> = []) {
    return [...rows].sort((x, y) => {
      for (const order of orderBy) {
        const [field, direction] = Object.entries(order)[0];
        const a = (x as unknown as Row)[field] as number | Date;
        const b = (y as unknown as Row)[field] as number | Date;
        const diff = Number(a) - Number(b);
        if (diff !== 0) return direction === "asc" ? diff : -diff;
      }
      return 0;
    });
  }

  function assertWindow(offer: FakeOffer) {
    if (
      offer.startsAt &&
      offer.endsBefore &&
      !(offer.endsBefore.getTime() > offer.startsAt.getTime())
    ) {
      throw constraintError();
    }
  }

  const prisma = {
    // Exposed for assertions.
    _stores: stores,
    _offers: offers,
    _images: images,

    store: {
      findUnique: jest.fn(async ({ where, select }: any) => {
        const store = stores.get(where.id);
        if (!store) return null;
        return select
          ? Object.fromEntries(Object.keys(select).map((k) => [k, (store as any)[k]]))
          : { ...store };
      }),
      findFirst: jest.fn(async ({ where, select }: any) => {
        const store = [...stores.values()].find((s) => matches(s as any, where));
        if (!store) return null;
        return select
          ? Object.fromEntries(Object.keys(select).map((k) => [k, (store as any)[k]]))
          : { ...store };
      }),
      // Offer code must never write to stores.
      create: jest.fn(),
      update: jest.fn(),
      updateMany: jest.fn(),
      delete: jest.fn(),
      deleteMany: jest.fn(),
      upsert: jest.fn(),
    },

    storeOffer: {
      findMany: jest.fn(async (args: any = {}) =>
        sort(
          [...offers.values()].filter((o) => matches(o as any, args.where)),
          args.orderBy,
        ).map((o) => project(o, args)),
      ),
      findUnique: jest.fn(async (args: any) => {
        const offer = offers.get(args.where.id);
        return offer ? project(offer, args) : null;
      }),
      findFirst: jest.fn(async (args: any) => {
        const offer = sort(
          [...offers.values()].filter((o) => matches(o as any, args.where)),
          args.orderBy,
        )[0];
        return offer ? project(offer, args) : null;
      }),
      create: jest.fn(async (args: any) => {
        const { data } = args;
        if (!stores.has(data.storeId)) {
          throw new Prisma.PrismaClientKnownRequestError("Foreign key constraint failed", {
            code: "P2003",
            clientVersion: "test",
          });
        }
        const now = nextTime();
        const offer: FakeOffer = {
          id: randomUUID(),
          description: "",
          discountLabel: null,
          imageVersion: 0,
          startsAt: null,
          endsBefore: null,
          isActive: true,
          displayOrder: 0,
          ...data,
          createdAt: now,
          updatedAt: now,
        };
        assertWindow(offer);
        offers.set(offer.id, offer);
        return project(offer, args);
      }),
      update: jest.fn(async (args: any) => {
        const current = offers.get(args.where.id);
        if (!current) throw notFound();
        const next: FakeOffer = { ...current, updatedAt: nextTime() };
        for (const [key, value] of Object.entries(args.data as Row)) {
          if (key === "image") {
            const payload = (value as any).upsert;
            const existing = images.get(current.id);
            images.set(current.id, {
              offerId: current.id,
              ...(existing ? payload.update : payload.create),
              updatedAt: next.updatedAt,
            });
          } else if (value && typeof value === "object" && "increment" in value) {
            (next as any)[key] = (current as any)[key] + (value as any).increment;
          } else {
            (next as any)[key] = value;
          }
        }
        assertWindow(next);
        offers.set(next.id, next);
        return project(next, args);
      }),
      delete: jest.fn(async ({ where }: any) => {
        const current = offers.get(where.id);
        if (!current) throw notFound();
        offers.delete(where.id);
        images.delete(where.id); // ON DELETE CASCADE
        return { ...current };
      }),
      // Offer code must never bulk-modify offers.
      deleteMany: jest.fn(),
      updateMany: jest.fn(),
    },

    storeOfferImage: {
      findUnique: jest.fn(async ({ where, select }: any) => {
        const image = images.get(where.offerId);
        if (!image) return null;
        return select
          ? Object.fromEntries(Object.keys(select).map((k) => [k, (image as any)[k]]))
          : { ...image };
      }),
      deleteMany: jest.fn(async ({ where }: any) => {
        const existed = images.delete(where.offerId);
        return { count: existed ? 1 : 0 };
      }),
    },

    $transaction: jest.fn((ops: Promise<unknown>[]) => Promise.all(ops)),
  };
  return prisma;
}

export type FakeOffersPrisma = ReturnType<typeof createFakeOffersPrisma>;

// ---------------------------------------------------------------- images

export function pngBytes(size = 64): Buffer {
  const bytes = Buffer.alloc(size, 0x11);
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).copy(bytes);
  return bytes;
}

export function jpegBytes(size = 64): Buffer {
  const bytes = Buffer.alloc(size, 0x22);
  Buffer.from([0xff, 0xd8, 0xff, 0xe0]).copy(bytes);
  return bytes;
}

export function webpBytes(size = 64): Buffer {
  const bytes = Buffer.alloc(size, 0x33);
  bytes.write("RIFF", 0, "ascii");
  bytes.write("WEBP", 8, "ascii");
  return bytes;
}

export function gifBytes(size = 64): Buffer {
  const bytes = Buffer.alloc(size, 0x44);
  bytes.write("GIF89a", 0, "ascii");
  return bytes;
}
