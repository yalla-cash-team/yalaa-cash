/**
 * Staging-only integration check: fractional points, point balance conversion,
 * individual (per-month) merchant settlement and duplicate prevention.
 *
 * Safety:
 * - Refuses to run unless DATABASE_URL's host starts with "ep-green-queen-".
 * - Does NOT load .env. Run it from a terminal where DATABASE_URL is already
 *   set to the staging connection. Existing variables are never overridden.
 * - Creates only synthetic rows whose names start with "itest-" and removes
 *   them at the end. Aborts before changing anything if other staging data
 *   would be affected (other customers with balances, other open merchants).
 * - Sends no notifications and triggers no payments.
 *
 * Run with ts-node (tsx does not emit decorator metadata, so Nest cannot inject):
 *   npx ts-node scripts/staging-integration.ts
 */
import { Test } from "@nestjs/testing";
import { Prisma } from "@prisma/client";
import { randomUUID } from "crypto";
import { AppModule } from "../src/app.module";
import { AdminService } from "../src/admin/admin.service";
import { LinkSyriaOtpService } from "../src/auth/linksyria/linksyria-otp.service";
import { LoyaltyCalculator } from "../src/loyalty/loyalty-calculator";
import { PrismaService } from "../src/prisma/prisma.service";

// Test-only stand-in for LinkSyria OTP. The production service is untouched.
// It never sends SMS and never calls the external API; any send attempt fails.
const linkSyriaStub = {
  isConfigured: () => false,
  send: () => {
    throw new Error("OTP sending is disabled in the staging integration test.");
  },
};

const REQUIRED_HOST_PREFIX = "ep-green-queen-";
const TAG = `itest-${Date.now()}`;

function fail(message: string): never {
  console.error(`FAIL: ${message}`);
  process.exit(1);
}

// Throws instead of exiting, so the finally block always runs cleanup.
function assert(condition: unknown, message: string): void {
  if (!condition) throw new Error(`ASSERTION FAILED: ${message}`);
  console.log(`  ok - ${message}`);
}

function checkStagingHost(): void {
  const raw = process.env.DATABASE_URL ?? "";
  let host = "";
  try {
    host = new URL(raw).hostname;
  } catch {
    fail("DATABASE_URL is missing or not a valid URL.");
  }
  if (!host.startsWith(REQUIRED_HOST_PREFIX)) {
    fail("DATABASE_URL does not point to the staging database. Nothing was run.");
  }
  console.log("Staging host check passed.");
}

function previousMonth(now: Date): { key: string; date: Date } {
  const date = new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 1, 15, 12),
  );
  const key = `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, "0")}`;
  return { key, date };
}

async function main(): Promise<void> {
  checkStagingHost();

  // Nest injects constructor parameters from decorator metadata. Runners that
  // skip it (such as tsx/esbuild) leave dependencies undefined, which breaks
  // AdminService. Fail early with a clear message instead.
  const reflect = Reflect as unknown as {
    getMetadata?: (key: string, target: object) => unknown;
  };
  if (!reflect.getMetadata?.("design:paramtypes", AdminService)) {
    fail("Decorator metadata is missing. Run with ts-node, not tsx.");
  }

  // The OTP provider is replaced for this process only; the module graph and
  // every other provider are the production ones.
  const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
    .overrideProvider(LinkSyriaOtpService)
    .useValue(linkSyriaStub)
    .compile();
  const prisma = moduleRef.get(PrismaService);
  const admin = moduleRef.get(AdminService);

  const created = {
    governorateId: null as string | null,
    storeId: null as string | null,
    customerUserId: null as string | null,
    merchantUserId: null as string | null,
  };
  const originalSettings = await prisma.platformSettings.findUniqueOrThrow({
    where: { id: 1 },
  });

  try {
    // Safety pre-checks: abort before any change if unrelated data exists.
    const otherBalances = await prisma.customerProfile.count({
      where: {
        OR: [{ pointsBalance: { gt: 0 } }, { pointRemainderSyp: { gt: 0 } }],
      },
    });
    assert(
      otherBalances === 0,
      "staging has no other customer balances (conversion would touch them)",
    );
    const pendingRequests =
      (await prisma.cashRedemptionRequest.count({ where: { status: "PENDING" } })) +
      (await prisma.productRedemption.count({ where: { status: "PENDING" } }));
    assert(pendingRequests === 0, "staging has no pending redemptions");

    const month = previousMonth(new Date());
    const preview = await admin.previewMonthlySettlement({ month: month.key });
    const otherOpen = preview.merchants.filter((m) => m.status === "open");
    assert(
      otherOpen.length === 0,
      `no other merchants have open invoices for ${month.key}`,
    );

    // 1. Synthetic data.
    const governorate = await prisma.governorate.create({
      data: { nameAr: `${TAG}-gov`, isActive: false },
    });
    created.governorateId = governorate.id;
    const merchantUser = await prisma.user.create({
      data: { role: "MERCHANT", isActive: false },
    });
    created.merchantUserId = merchantUser.id;
    const store = await prisma.store.create({
      data: {
        name: `${TAG}-store`,
        category: "itest",
        city: "itest",
        commissionRate: new Prisma.Decimal(10),
        governorateId: governorate.id,
        isActive: false,
      },
    });
    created.storeId = store.id;
    await prisma.merchantAccount.create({
      data: { userId: merchantUser.id, storeId: store.id, isActive: false },
    });
    const customerUser = await prisma.user.create({
      data: { role: "CUSTOMER", isActive: false },
    });
    created.customerUserId = customerUser.id;
    await prisma.customerProfile.create({
      data: {
        userId: customerUser.id,
        name: `${TAG}-customer`,
        governorate: `${TAG}-gov`,
      },
    });
    console.log("Synthetic rows created.");

    // Value the synthetic balances at 0.30 SYP per point. This must happen
    // before any balance is created: conversion re-values every balance using
    // the value that is current at the time of the change.
    await admin.updateSettings({ pointValueSyp: 0.3 });

    // 2. Fractional points at 0.30 SYP per point (share 5 SYP).
    const earn = LoyaltyCalculator.calculate({
      invoiceAmountSyp: 100,
      commissionRate: 10,
      pointValueSyp: "0.3",
    });
    assert(earn.customerPoints === 16, "0.30 SYP: 5 SYP earns 16 points");
    await prisma.customerProfile.update({
      where: { userId: customerUser.id },
      data: {
        pointsBalance: BigInt(earn.customerPoints),
        pointRemainderSyp: earn.customerRemainderSyp,
      },
    });
    const saved = await prisma.customerProfile.findUniqueOrThrow({
      where: { userId: customerUser.id },
    });
    assert(
      saved.pointRemainderSyp.equals(new Prisma.Decimal("0.2")),
      "remainder 0.2 SYP is saved exactly",
    );

    // 3. Conversion keeps the monetary balance (5 SYP) in both directions.
    await admin.updateSettings({ pointValueSyp: 5 });
    const toFive = await prisma.customerProfile.findUniqueOrThrow({
      where: { userId: customerUser.id },
    });
    assert(
      toFive.pointsBalance === BigInt(1) &&
        toFive.pointRemainderSyp.equals(new Prisma.Decimal(0)),
      "0.30 -> 5 SYP: 4.8 + 0.2 = 5 SYP becomes 1 point, no remainder",
    );
    await admin.updateSettings({ pointValueSyp: 0.1 });
    const toTenth = await prisma.customerProfile.findUniqueOrThrow({
      where: { userId: customerUser.id },
    });
    assert(
      toTenth.pointsBalance === BigInt(50) &&
        toTenth.pointRemainderSyp.equals(new Prisma.Decimal(0)),
      "5 -> 0.10 SYP: 5 SYP becomes 50 points, no monetary loss",
    );

    // 4. Individual (per-month) settlement, using a real invoice in last month.
    const amount = BigInt(100000);
    await prisma.loyaltyTransaction.create({
      data: {
        storeId: store.id,
        customerId: customerUser.id,
        merchantAccountId: (
          await prisma.merchantAccount.findUniqueOrThrow({
            where: { userId: merchantUser.id },
          })
        ).id,
        amountSyp: amount,
        commissionRateSnapshot: new Prisma.Decimal(10),
        commissionAmountSyp: BigInt(10000),
        platformRevenueSyp: BigInt(5000),
        customerShareSyp: BigInt(5000),
        pointValueSypSnapshot: new Prisma.Decimal(0.1),
        customerPointsEarned: BigInt(50000),
        idempotencyKey: randomUUID(),
        createdAt: month.date,
      },
    });
    const txBefore = await prisma.loyaltyTransaction.count({
      where: { storeId: store.id },
    });

    const first = await admin.runMonthlySettlement(merchantUser.id, {
      month: month.key,
    });
    const ours = first.merchants.find((m) => m.storeId === store.id);
    assert(ours?.status === "settled", "monthly run settles our merchant");

    const rows = await prisma.merchantSettlement.findMany({
      where: { storeId: store.id, kind: "MONTHLY" },
    });
    assert(rows.length === 1, "exactly one monthly settlement row exists");
    assert(
      rows[0].commissionDueSyp === BigInt(10000) &&
        rows[0].transactionCount === 1,
      "settlement totals match the invoice (commission 10000, 1 invoice)",
    );

    // 5. Duplicate prevention: a second run must not create another row.
    const second = await admin.runMonthlySettlement(merchantUser.id, {
      month: month.key,
    });
    const again = second.merchants.find((m) => m.storeId === store.id);
    assert(
      again === undefined || again.status !== "settled",
      "second run does not settle the same month again",
    );
    const rowsAfter = await prisma.merchantSettlement.count({
      where: { storeId: store.id, kind: "MONTHLY" },
    });
    assert(rowsAfter === 1, "still exactly one monthly row after a second run");

    // 6. History preserved.
    const txAfter = await prisma.loyaltyTransaction.count({
      where: { storeId: store.id },
    });
    assert(txAfter === txBefore, "invoice history is unchanged by settlement");

    console.log("PASS: all staging integration checks succeeded.");
  } finally {
    // Every cleanup step runs even if an earlier one fails, so one error can
    // never skip the point-value restore. Failures are reported, not hidden.
    const cleanupErrors: unknown[] = [];
    const step = async (label: string, action: () => Promise<unknown>) => {
      try {
        await action();
      } catch (error) {
        cleanupErrors.push(error);
        console.error(`CLEANUP FAILED: ${label}`);
      }
    };
    if (created.storeId) {
      const storeId = created.storeId;
      await step("settlements", () =>
        prisma.merchantSettlement.deleteMany({ where: { storeId } }));
      await step("invoices", () =>
        prisma.loyaltyTransaction.deleteMany({ where: { storeId } }));
      await step("merchant accounts", () =>
        prisma.merchantAccount.deleteMany({ where: { storeId } }));
    }
    if (created.customerUserId) {
      const customerId = created.customerUserId;
      await step("customer ledger", () =>
        prisma.pointsLedgerEntry.deleteMany({ where: { customerId } }));
      await step("customer profile", () =>
        prisma.customerProfile.deleteMany({ where: { userId: customerId } }));
    }
    if (created.storeId) {
      const id = created.storeId;
      await step("store", () => prisma.store.deleteMany({ where: { id } }));
    }
    for (const id of [created.customerUserId, created.merchantUserId]) {
      if (id) await step("user", () => prisma.user.deleteMany({ where: { id } }));
    }
    if (created.governorateId) {
      const id = created.governorateId;
      await step("governorate", () =>
        prisma.governorate.deleteMany({ where: { id } }));
    }
    await step("restore point value", () =>
      prisma.platformSettings.update({
        where: { id: 1 },
        data: { pointValueSyp: originalSettings.pointValueSyp },
      }));
    await step("close app", () => moduleRef.close());
    if (cleanupErrors.length === 0) {
      console.log("Synthetic data removed and point value restored.");
    } else {
      console.error(
        `CLEANUP INCOMPLETE: ${cleanupErrors.length} step(s) failed. Check rows with the itest- prefix.`,
      );
      process.exitCode = 1;
    }
  }
}

main().catch((error: unknown) => {
  // The full stack is printed so the failing line is visible. Only synthetic
  // (itest-) values can appear in messages from this script's own queries.
  console.error("FAIL: unhandled error");
  console.error(error instanceof Error ? (error.stack ?? error.message) : String(error));
  process.exit(1);
});
