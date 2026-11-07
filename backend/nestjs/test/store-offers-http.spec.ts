import { INestApplication, ValidationPipe } from "@nestjs/common";
import { APP_GUARD } from "@nestjs/core";
import { JwtService } from "@nestjs/jwt";
import { Test } from "@nestjs/testing";
import { UserRole } from "@prisma/client";
import { json } from "express";
import { IS_PUBLIC_KEY, ROLES_KEY } from "../src/auth/auth.constants";
import { JwtAuthGuard } from "../src/auth/guards/jwt-auth.guard";
import { RolesGuard } from "../src/auth/guards/roles.guard";
import { AdminOffersController } from "../src/offers/admin-offers.controller";
import { OffersModule } from "../src/offers/offers.module";
import { PublicOffersController } from "../src/offers/public-offers.controller";
import { PrismaModule } from "../src/prisma/prisma.module";
import { PrismaService } from "../src/prisma/prisma.service";
import {
  createFakeOffersPrisma,
  fakeStore,
  FakeOffersPrisma,
  gifBytes,
  INACTIVE_STORE,
  MISSING_ID,
  pngBytes,
  STORE_A,
  STORE_B,
  webpBytes,
} from "./support/fake-offers-prisma";

/**
 * HTTP-level tests: the offers module behind the real global JwtAuthGuard,
 * RolesGuard and ValidationPipe (same options as main.ts), with PrismaService
 * replaced by the in-memory fake. Listens on 127.0.0.1 only; no database.
 */

const OFFER_1 = "11111111-1111-4111-8111-111111111111";
const OFFER_B = "22222222-2222-4222-8222-222222222222";

const TOKENS: Record<string, { sub: string; role: UserRole }> = {
  "admin-token": { sub: "u-admin", role: UserRole.ADMIN },
  "customer-token": { sub: "u-customer", role: UserRole.CUSTOMER },
  "merchant-token": { sub: "u-merchant", role: UserRole.MERCHANT },
};

let app: INestApplication;
let baseUrl: string;
let prisma: FakeOffersPrisma & { user: { findUnique: jest.Mock } };

async function buildApp() {
  prisma = Object.assign(
    createFakeOffersPrisma({
      stores: [
        fakeStore({ id: STORE_A }),
        fakeStore({ id: STORE_B }),
        fakeStore({ id: INACTIVE_STORE, isActive: false }),
      ],
      offers: [
        { id: OFFER_1, storeId: STORE_A, title: "First", imageVersion: 1 },
        { id: OFFER_B, storeId: STORE_B, title: "Other store" },
      ],
      images: [
        { offerId: OFFER_1, contentType: "image/png", data: pngBytes(), updatedAt: new Date() },
      ],
    }),
    {
      user: {
        findUnique: jest.fn(async ({ where }: any) => {
          const entry = Object.values(TOKENS).find((t) => t.sub === where.id);
          return entry ? { id: entry.sub, role: entry.role, isActive: true } : null;
        }),
      },
    },
  );

  const moduleRef = await Test.createTestingModule({
    imports: [PrismaModule, OffersModule],
    providers: [
      {
        provide: JwtService,
        useValue: {
          verifyAsync: async (token: string) => {
            const payload = TOKENS[token];
            if (!payload) throw new Error("invalid token");
            return payload;
          },
        },
      },
      { provide: APP_GUARD, useClass: JwtAuthGuard },
      { provide: APP_GUARD, useClass: RolesGuard },
    ],
  })
    .overrideProvider(PrismaService)
    .useValue(prisma)
    .compile();

  app = moduleRef.createNestApplication({ bodyParser: false });
  app.use(json({ limit: "1mb" }));
  app.useGlobalPipes(
    new ValidationPipe({ whitelist: true, transform: true, forbidNonWhitelisted: true }),
  );
  await app.listen(0, "127.0.0.1");
  baseUrl = (await app.getUrl()).replace("[::1]", "127.0.0.1");
}

async function call(
  method: string,
  path: string,
  options: { token?: string; body?: unknown } = {},
) {
  const headers: Record<string, string> = {};
  if (options.token) headers.authorization = `Bearer ${options.token}`;
  if (options.body !== undefined) headers["content-type"] = "application/json";
  const response = await fetch(`${baseUrl}${path}`, {
    method,
    headers,
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
  });
  const type = response.headers.get("content-type") ?? "";
  const body = type.includes("json") ? await response.json() : Buffer.from(await response.arrayBuffer());
  return { status: response.status, headers: response.headers, body: body as any };
}

const admin = (method: string, path: string, body?: unknown) =>
  call(method, path, { token: "admin-token", body });

beforeEach(buildApp);
afterEach(async () => {
  await app.close();
});

// Every row has exactly three elements: with fewer, it.each would pass the
// missing argument as a `done` callback and the test would wait for it.
const ADMIN_ROUTES: Array<[string, string, unknown]> = [
  ["GET", `/admin/stores/${STORE_A}/offers`, undefined],
  ["POST", `/admin/stores/${STORE_A}/offers`, { title: "عرض" }],
  ["PATCH", `/admin/offers/${OFFER_1}`, { title: "عرض" }],
  ["DELETE", `/admin/offers/${OFFER_1}`, undefined],
  ["POST", `/admin/offers/${OFFER_1}/image`, { contentType: "image/png", dataBase64: pngBytes().toString("base64") }],
  ["DELETE", `/admin/offers/${OFFER_1}/image`, undefined],
  ["GET", `/admin/offers/${OFFER_1}/image`, undefined],
];

describe("authorization", () => {
  it("declares admin-only at class level and never marks admin routes public", () => {
    expect(Reflect.getMetadata(ROLES_KEY, AdminOffersController)).toEqual([UserRole.ADMIN]);
    expect(Reflect.getMetadata(IS_PUBLIC_KEY, AdminOffersController)).toBeUndefined();
    for (const name of Object.getOwnPropertyNames(AdminOffersController.prototype)) {
      if (name === "constructor") continue;
      const handler = (AdminOffersController.prototype as any)[name];
      expect(Reflect.getMetadata(IS_PUBLIC_KEY, handler)).toBeUndefined();
      expect(Reflect.getMetadata(ROLES_KEY, handler)).toBeUndefined();
    }
  });

  it("marks only the two customer read endpoints as public", () => {
    for (const name of ["list", "image"]) {
      const handler = (PublicOffersController.prototype as any)[name];
      expect(Reflect.getMetadata(IS_PUBLIC_KEY, handler)).toBe(true);
    }
  });

  it.each(ADMIN_ROUTES)("%s %s -> 401 without a token", async (method, path, body) => {
    expect((await call(method, path, { body })).status).toBe(401);
    expect((await call(method, path, { body, token: "forged" })).status).toBe(401);
  });

  it.each(ADMIN_ROUTES)("%s %s -> 403 for customers and merchants", async (method, path, body) => {
    expect((await call(method, path, { body, token: "customer-token" })).status).toBe(403);
    expect((await call(method, path, { body, token: "merchant-token" })).status).toBe(403);
  });

  it("leaves data untouched after rejected non-admin attempts", async () => {
    for (const [method, path, body] of ADMIN_ROUTES) {
      await call(method, path, { body, token: "customer-token" });
    }
    expect(prisma._offers.size).toBe(2);
    expect(prisma._offers.get(OFFER_1)!.title).toBe("First");
    expect(prisma._images.has(OFFER_1)).toBe(true);
  });
});

describe("admin endpoints", () => {
  it("lists, creates, updates, deactivates and deletes", async () => {
    const created = await admin("POST", `/admin/stores/${STORE_A}/offers`, {
      title: "  خصم الشتاء  ",
      description: "على جميع المشروبات",
      discountLabel: "خصم 20%",
      startDate: "2026-11-01",
      endDate: "2026-11-30",
      displayOrder: 1,
    });
    expect(created.status).toBe(201);
    expect(created.body).toMatchObject({
      title: "خصم الشتاء",
      startsAt: "2026-10-31T21:00:00.000Z",
      endsBefore: "2026-11-30T21:00:00.000Z",
      startDate: "2026-11-01",
      endDate: "2026-11-30",
    });
    const newId = created.body.id;

    const list = await admin("GET", `/admin/stores/${STORE_A}/offers`);
    expect(list.status).toBe(200);
    expect(list.body.map((o: any) => o.id)).toEqual([OFFER_1, newId]);

    const off = await admin("PATCH", `/admin/offers/${newId}`, { isActive: false });
    expect(off.status).toBe(200);
    expect(off.body).toMatchObject({ isActive: false, status: "inactive", title: "خصم الشتاء" });

    const deleted = await admin("DELETE", `/admin/offers/${newId}`);
    expect(deleted.status).toBe(200);
    expect(deleted.body).toEqual({ id: newId, storeId: STORE_A, deleted: true });
    expect(prisma._offers.has(OFFER_1)).toBe(true);
    expect(prisma._offers.has(OFFER_B)).toBe(true);
  });

  it.each([
    ["title too short (after trimming)", { title: "  a  " }],
    ["title too long", { title: "x".repeat(121) }],
    ["title missing", {}],
    ["title not a string", { title: 12 }],
    ["description too long", { title: "عرض", description: "x".repeat(1001) }],
    ["discount label too long", { title: "عرض", discountLabel: "x".repeat(61) }],
    ["negative displayOrder", { title: "عرض", displayOrder: -1 }],
    ["displayOrder too large", { title: "عرض", displayOrder: 10000 }],
    ["fractional displayOrder", { title: "عرض", displayOrder: 1.5 }],
    ["string displayOrder", { title: "عرض", displayOrder: "3" }],
    ["string isActive", { title: "عرض", isActive: "true" }],
    ["timestamp instead of a date", { title: "عرض", startDate: "2026-11-01T00:00:00Z" }],
    ["browser-style date", { title: "عرض", endDate: "11/30/2026" }],
    ["impossible date", { title: "عرض", endDate: "2026-02-30" }],
    ["reversed range", { title: "عرض", startDate: "2026-11-10", endDate: "2026-11-09" }],
    ["storeId in body", { title: "عرض", storeId: STORE_B }],
    ["store city", { title: "عرض", city: "Aleppo" }],
    ["store category", { title: "عرض", category: "Cafe" }],
    ["store exclusivity", { title: "عرض", isExclusive: false }],
    ["imageVersion", { title: "عرض", imageVersion: 99 }],
    ["points field", { title: "عرض", points: 100 }],
  ])("POST rejects %s with 400", async (_label, body) => {
    const response = await admin("POST", `/admin/stores/${STORE_A}/offers`, body);
    expect(response.status).toBe(400);
    expect(prisma.storeOffer.create).not.toHaveBeenCalled();
  });

  it("accepts the length limits exactly", async () => {
    const response = await admin("POST", `/admin/stores/${STORE_A}/offers`, {
      title: "x".repeat(120),
      description: "d".repeat(1000),
      discountLabel: "l".repeat(60),
      displayOrder: 9999,
    });
    expect(response.status).toBe(201);
    expect((await admin("POST", `/admin/stores/${STORE_A}/offers`, { title: "ab", displayOrder: 0 })).status).toBe(201);
  });

  it.each([
    ["null title", { title: null }],
    ["null isActive", { isActive: null }],
    ["null displayOrder", { displayOrder: null }],
    ["storeId", { storeId: STORE_B }],
    ["end before stored start", { startDate: "2026-11-10", endDate: "2026-11-09" }],
  ])("PATCH rejects %s with 400", async (_label, body) => {
    const response = await admin("PATCH", `/admin/offers/${OFFER_1}`, body);
    expect(response.status).toBe(400);
    expect(prisma._offers.get(OFFER_1)!.storeId).toBe(STORE_A);
    expect(prisma._offers.get(OFFER_1)!.title).toBe("First");
  });

  it("PATCH validates a partial date against the stored boundary", async () => {
    expect((await admin("PATCH", `/admin/offers/${OFFER_1}`, { startDate: "2026-11-10" })).status).toBe(200);
    expect((await admin("PATCH", `/admin/offers/${OFFER_1}`, { endDate: "2026-11-09" })).status).toBe(400);
    const ok = await admin("PATCH", `/admin/offers/${OFFER_1}`, { endDate: "2026-11-10" });
    expect(ok.status).toBe(200);
    expect([ok.body.startDate, ok.body.endDate]).toEqual(["2026-11-10", "2026-11-10"]);
    const cleared = await admin("PATCH", `/admin/offers/${OFFER_1}`, { startDate: null });
    expect(cleared.body).toMatchObject({ startDate: null, endDate: "2026-11-10" });
  });

  it("returns 404 for missing stores and offers", async () => {
    expect((await admin("GET", `/admin/stores/${MISSING_ID}/offers`)).status).toBe(404);
    expect((await admin("POST", `/admin/stores/${MISSING_ID}/offers`, { title: "عرض" })).status).toBe(404);
    expect((await admin("PATCH", `/admin/offers/${MISSING_ID}`, { title: "عرض" })).status).toBe(404);
    expect((await admin("DELETE", `/admin/offers/${MISSING_ID}`)).status).toBe(404);
    expect((await admin("POST", `/admin/offers/${MISSING_ID}/image`, {
      contentType: "image/png",
      dataBase64: pngBytes().toString("base64"),
    })).status).toBe(404);
    expect((await admin("DELETE", `/admin/offers/${MISSING_ID}/image`)).status).toBe(404);
    expect((await admin("GET", `/admin/offers/${MISSING_ID}/image`)).status).toBe(404);
  });

  it("returns 400 for malformed ids instead of reaching the database", async () => {
    expect((await admin("GET", "/admin/stores/not-a-uuid/offers")).status).toBe(400);
    expect((await admin("DELETE", "/admin/offers/1")).status).toBe(400);
    expect((await admin("PATCH", "/admin/offers/abc", { title: "عرض" })).status).toBe(400);
    expect(prisma.storeOffer.delete).not.toHaveBeenCalled();
  });

  it("uploads, replaces and removes an image with version bumps", async () => {
    const upload = await admin("POST", `/admin/offers/${OFFER_1}/image`, {
      contentType: "image/webp",
      dataBase64: webpBytes().toString("base64"),
    });
    expect(upload.status).toBe(200);
    expect(upload.body).toMatchObject({ imageVersion: 2, imageUrl: `/admin/offers/${OFFER_1}/image?v=2` });

    const preview = await admin("GET", `/admin/offers/${OFFER_1}/image`);
    expect(preview.status).toBe(200);
    expect(preview.headers.get("content-type")).toBe("image/webp");
    expect(preview.headers.get("cache-control")).toBe("private, max-age=86400");

    const removed = await admin("DELETE", `/admin/offers/${OFFER_1}/image`);
    expect(removed.body).toMatchObject({ imageVersion: 3, imageUrl: null, hasImage: false });
  });

  it.each([
    ["GIF", { contentType: "image/gif", dataBase64: gifBytes().toString("base64") }],
    ["oversized", { contentType: "image/png", dataBase64: pngBytes(300 * 1024 + 1).toString("base64") }],
    ["bad base64", { contentType: "image/png", dataBase64: "@@@" }],
    ["lying type", { contentType: "image/jpeg", dataBase64: pngBytes().toString("base64") }],
    ["missing data", { contentType: "image/png" }],
    ["extra field", { contentType: "image/png", dataBase64: pngBytes().toString("base64"), offerId: OFFER_B }],
  ])("rejects a %s image upload with 400", async (_label, body) => {
    const response = await admin("POST", `/admin/offers/${OFFER_1}/image`, body);
    expect(response.status).toBe(400);
    expect(prisma._offers.get(OFFER_1)!.imageVersion).toBe(1);
  });
});

describe("public endpoints", () => {
  it("lists a store's visible offers without authentication", async () => {
    const response = await call("GET", `/stores/${STORE_A}/offers`);
    expect(response.status).toBe(200);
    expect(response.body).toEqual([
      expect.objectContaining({ id: OFFER_1, imageUrl: `/offers/${OFFER_1}/image?v=1` }),
    ]);
  });

  it("returns 404 for an inactive store and 400 for a malformed id", async () => {
    expect((await call("GET", `/stores/${INACTIVE_STORE}/offers`)).status).toBe(404);
    expect((await call("GET", "/stores/nope/offers")).status).toBe(400);
  });

  it("serves a visible offer's image with type, cache and CORP headers", async () => {
    const response = await call("GET", `/offers/${OFFER_1}/image`);
    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toBe("image/png");
    expect(response.headers.get("cache-control")).toBe("public, max-age=86400");
    expect(response.headers.get("cross-origin-resource-policy")).toBe("cross-origin");
    expect(Buffer.compare(response.body, pngBytes())).toBe(0);
  });

  it("does not serve the image once the offer is deactivated", async () => {
    await admin("PATCH", `/admin/offers/${OFFER_1}`, { isActive: false });
    const response = await call("GET", `/offers/${OFFER_1}/image`);
    expect(response.status).toBe(404);
    expect(JSON.stringify(response.body)).not.toMatch(/StoreOfferImage|prisma|bytea/i);
  });
});
