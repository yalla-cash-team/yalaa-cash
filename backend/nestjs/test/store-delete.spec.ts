import { NotFoundException } from "@nestjs/common";
import { AdminService } from "../src/admin/admin.service";
import { MerchantService } from "../src/merchant/merchant.service";
import { StoresService } from "../src/stores/stores.service";

/**
 * Covers the "Delete Store" feature: this is a SOFT delete only.
 * AdminService.deleteStore() must:
 *   - never issue Store.delete / LoyaltyTransaction.delete /
 *     MerchantSettlement.delete / any *.update against historical rows,
 *   - set Store.isActive = false and every related MerchantAccount.isActive
 *     = false, in one transaction,
 *   - be safe to call repeatedly (idempotent, never throws on an
 *     already-inactive store).
 * It must also be effective everywhere that already depends on isActive:
 * Customer's active-store listing, and every merchant-protected operation
 * that already re-checks MerchantAccount.isActive on each call.
 */

const STORE_ID = "11111111-1111-1111-1111-111111111111";
const USER_ID = "22222222-2222-2222-2222-222222222222";

function fakeAdminPrisma(overrides: Record<string, unknown> = {}) {
  const prisma: any = {
    store: {
      findUnique: jest.fn().mockResolvedValue({
        id: STORE_ID,
        name: "Test Store",
        isActive: true,
      }),
      update: jest.fn().mockImplementation(({ data }: any) =>
        Promise.resolve({ id: STORE_ID, name: "Test Store", ...data }),
      ),
      delete: jest.fn(),
    },
    merchantAccount: {
      updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      update: jest.fn(),
      delete: jest.fn(),
    },
    loyaltyTransaction: {
      delete: jest.fn(),
      deleteMany: jest.fn(),
      update: jest.fn(),
      updateMany: jest.fn(),
    },
    merchantSettlement: {
      delete: jest.fn(),
      deleteMany: jest.fn(),
      update: jest.fn(),
      updateMany: jest.fn(),
    },
    ...overrides,
  };
  // Mirrors AdminService.deleteStore()'s array-style $transaction([...]) —
  // each element is already an invoked (Promise-returning) Prisma call.
  prisma.$transaction = jest.fn((arg: any) =>
    typeof arg === "function" ? arg(prisma) : Promise.all(arg),
  );
  return prisma;
}

describe("Delete Store (soft delete)", () => {
  it("sets Store.isActive to false", async () => {
    const prisma = fakeAdminPrisma();
    const admin = new AdminService(prisma as any, {} as any, {} as any);

    const result = await admin.deleteStore(STORE_ID);

    expect(result).toEqual({ success: true });
    expect(prisma.store.update).toHaveBeenCalledWith({
      where: { id: STORE_ID },
      data: { isActive: false, displayOrder: 0 },
    });
  });

  it("sets every related MerchantAccount.isActive to false in the same transaction", async () => {
    const prisma = fakeAdminPrisma();
    const admin = new AdminService(prisma as any, {} as any, {} as any);

    await admin.deleteStore(STORE_ID);

    expect(prisma.merchantAccount.updateMany).toHaveBeenCalledWith({
      where: { storeId: STORE_ID },
      data: { isActive: false },
    });
    // Both writes went through the SAME $transaction call.
    expect(prisma.$transaction).toHaveBeenCalledTimes(1);
  });

  it("never issues delete/update against LoyaltyTransaction or MerchantSettlement", async () => {
    const prisma = fakeAdminPrisma();
    const admin = new AdminService(prisma as any, {} as any, {} as any);

    await admin.deleteStore(STORE_ID);

    expect(prisma.loyaltyTransaction.delete).not.toHaveBeenCalled();
    expect(prisma.loyaltyTransaction.deleteMany).not.toHaveBeenCalled();
    expect(prisma.loyaltyTransaction.update).not.toHaveBeenCalled();
    expect(prisma.loyaltyTransaction.updateMany).not.toHaveBeenCalled();
    expect(prisma.merchantSettlement.delete).not.toHaveBeenCalled();
    expect(prisma.merchantSettlement.deleteMany).not.toHaveBeenCalled();
    expect(prisma.merchantSettlement.update).not.toHaveBeenCalled();
    expect(prisma.merchantSettlement.updateMany).not.toHaveBeenCalled();
  });

  it("never issues Store.delete or MerchantAccount.delete", async () => {
    const prisma = fakeAdminPrisma();
    const admin = new AdminService(prisma as any, {} as any, {} as any);

    await admin.deleteStore(STORE_ID);

    expect(prisma.store.delete).not.toHaveBeenCalled();
    expect(prisma.merchantAccount.delete).not.toHaveBeenCalled();
  });

  it("throws NotFoundException for a store that doesn't exist, without touching anything", async () => {
    const prisma = fakeAdminPrisma();
    prisma.store.findUnique.mockResolvedValue(null);
    const admin = new AdminService(prisma as any, {} as any, {} as any);

    await expect(admin.deleteStore("missing-store")).rejects.toBeInstanceOf(
      NotFoundException,
    );
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it("repeated delete on an already-inactive store is safe and idempotent", async () => {
    const prisma = fakeAdminPrisma();
    prisma.store.findUnique.mockResolvedValue({
      id: STORE_ID,
      name: "Test Store",
      isActive: false, // already deleted once
    });

    const admin = new AdminService(prisma as any, {} as any, {} as any);

    const first = await admin.deleteStore(STORE_ID);
    const second = await admin.deleteStore(STORE_ID);

    expect(first).toEqual({ success: true });
    expect(second).toEqual({ success: true });
    expect(prisma.$transaction).toHaveBeenCalledTimes(2);
    // Each call still only ever sets isActive: false — never anything else,
    // never a throw, never a duplicate/partial state.
    expect(prisma.store.update).toHaveBeenNthCalledWith(1, {
      where: { id: STORE_ID },
      data: { isActive: false, displayOrder: 0 },
    });
    expect(prisma.store.update).toHaveBeenNthCalledWith(2, {
      where: { id: STORE_ID },
      data: { isActive: false, displayOrder: 0 },
    });
  });

  it("Customer's active-store listing no longer returns a soft-deleted store", async () => {
    // listActiveStores() always filters isActive: true — a deactivated
    // store is simply absent from whatever Prisma returns for that filter.
    const prisma = {
      store: {
        findMany: jest.fn().mockResolvedValue([
          {
            id: "other-store",
            name: "Other Store",
            category: "مطاعم",
            city: "دمشق",
            commissionRate: 5,
            description: "",
            location: "",
            imageUrl: null,
            iconSeed: 0,
            isActive: true,
            governorateId: "gov-1",
            createdAt: new Date("2026-01-01T00:00:00.000Z"),
          },
          // STORE_ID intentionally NOT included: a real DB with
          // isActive: true in the WHERE clause would never return it.
        ]),
      },
    };
    const stores = new StoresService(prisma as any);

    const result = await stores.listActiveStores({} as any);

    expect(prisma.store.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ isActive: true }),
      }),
    );
    expect(result.items.some((item: any) => item.id === STORE_ID)).toBe(
      false,
    );
  });

  it("an inactive merchant account cannot register a new invoice, even with otherwise-valid auth", async () => {
    const prisma: any = {
      loyaltyTransaction: {
        findUnique: jest.fn().mockResolvedValue(null), // no idempotency replay
      },
      merchantAccount: {
        // The account row exists, but isActive is now false — the WHERE
        // clause (isActive: true) means Prisma finds nothing, exactly as it
        // would against a real database.
        findFirst: jest.fn().mockResolvedValue(null),
      },
    };
    prisma.$transaction = jest.fn((fn: any) => fn(prisma));
    // A structurally valid, already-verified QR token — proves the
    // rejection genuinely comes from the MerchantAccount.isActive check,
    // not from an unrelated QR-parsing failure.
    const jwt = {
      verifyAsync: jest.fn().mockResolvedValue({ sub: "customer-id" }),
    };
    const config = { getOrThrow: jest.fn().mockReturnValue("qr-secret") };
    const merchant = new MerchantService(prisma as any, jwt as any, config as any);

    await expect(
      merchant.registerInvoice(USER_ID, {
        customerQrPayload: "yallacash://customer?token=valid-token",
        amountSyp: 10_000,
        idempotencyKey: "33333333-3333-3333-3333-333333333333",
      } as any),
    ).rejects.toThrow("Merchant account is not active.");

    expect(prisma.merchantAccount.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({ where: { userId: USER_ID, isActive: true } }),
    );
  });

  it("an inactive merchant account cannot access its workspace/summary/transactions/devices either", async () => {
    const prisma: any = {
      merchantAccount: {
        findFirst: jest.fn().mockResolvedValue(null), // isActive: true finds nothing
      },
    };
    const merchant = new MerchantService(prisma as any, {} as any, {} as any);

    await expect(merchant.getWorkspace(USER_ID)).rejects.toThrow(
      "Merchant account is not active.",
    );
    await expect(merchant.getSummary(USER_ID, {})).rejects.toThrow(
      "Merchant account is not active.",
    );
    await expect(
      merchant.listTransactions(USER_ID, { limit: 10 } as any),
    ).rejects.toThrow("Merchant account is not active.");
    await expect(
      merchant.registerDevice(USER_ID, {
        fingerprint: "fp",
        label: "device",
      } as any),
    ).rejects.toThrow("Merchant account is not active.");
  });
});
