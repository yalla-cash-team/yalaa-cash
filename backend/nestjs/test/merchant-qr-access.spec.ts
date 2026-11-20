import { ForbiddenException } from "@nestjs/common";
import { MerchantController } from "../src/merchant/merchant.controller";
import { MerchantService } from "../src/merchant/merchant.service";

/**
 * Regression tests for the security audit finding
 * merchant-qr-resolve-skips-active-account-check: an inactive merchant
 * account, or a merchant of an inactive (soft-deleted) store, must not be
 * able to read customer details from a QR code.
 */

const MERCHANT_USER = "22222222-2222-4222-8222-222222222222";
const CUSTOMER_ID = "33333333-3333-4333-8333-333333333333";
const QR = `yallacash://customer/${CUSTOMER_ID}?v=2&token=dummy.jwt.token`;

function setup(account: { storeActive: boolean } | null) {
  const prisma = {
    merchantAccount: {
      findFirst: jest.fn().mockResolvedValue(
        account
          ? {
              id: "acct-1",
              storeId: "store-1",
              isActive: true,
              store: { id: "store-1", isActive: account.storeActive },
            }
          : null,
      ),
    },
    customerProfile: {
      findUnique: jest.fn().mockResolvedValue({
        userId: CUSTOMER_ID,
        name: "Dummy Customer",
        governorate: "",
        governorateId: null,
        cityId: null,
        pointsBalance: 10n,
        createdAt: new Date(0),
        user: { phone: "+963900000001", authMethod: "PHONE" },
      }),
    },
  };
  const jwt = {
    verifyAsync: jest.fn().mockResolvedValue({ sub: CUSTOMER_ID, aud: "merchant-scan" }),
  };
  const config = { getOrThrow: jest.fn(() => "q".repeat(32)) };
  const service = new MerchantService(prisma as never, jwt as never, config as never);
  return { prisma, jwt, service };
}

describe("Finding merchant-qr-resolve-skips-active-account-check", () => {
  it("blocks an inactive merchant account before the QR is even decoded", async () => {
    const t = setup(null);
    await expect(
      t.service.resolveCustomerQr(MERCHANT_USER, { payload: QR }),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(t.prisma.merchantAccount.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({ where: { userId: MERCHANT_USER, isActive: true } }),
    );
    expect(t.jwt.verifyAsync).not.toHaveBeenCalled();
    expect(t.prisma.customerProfile.findUnique).not.toHaveBeenCalled();
  });

  it("blocks a merchant whose store is inactive or soft-deleted", async () => {
    const t = setup({ storeActive: false });
    await expect(
      t.service.resolveCustomerQr(MERCHANT_USER, { payload: QR }),
    ).rejects.toThrow("Store is not active.");
    expect(t.jwt.verifyAsync).not.toHaveBeenCalled();
    expect(t.prisma.customerProfile.findUnique).not.toHaveBeenCalled();
  });

  it("still resolves the customer for an active merchant of an active store", async () => {
    const t = setup({ storeActive: true });
    const customer = await t.service.resolveCustomerQr(MERCHANT_USER, { payload: QR });
    expect(customer).toMatchObject({ id: CUSTOMER_ID, name: "Dummy Customer" });
    expect(t.jwt.verifyAsync).toHaveBeenCalledWith("dummy.jwt.token", {
      secret: "q".repeat(32),
      audience: "merchant-scan",
    });
  });

  it("passes the authenticated merchant's id from the controller", async () => {
    const service = { resolveCustomerQr: jest.fn().mockResolvedValue({}) };
    const controller = new MerchantController(service as never);
    await controller.resolveCustomerQr(
      { id: MERCHANT_USER, role: "MERCHANT" } as never,
      { payload: QR },
    );
    expect(service.resolveCustomerQr).toHaveBeenCalledWith(MERCHANT_USER, { payload: QR });
  });
});
