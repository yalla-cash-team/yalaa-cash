/**
 * Staging-only cleanup of leftover integration-test records (names start
 * with "itest-"). Separate from the integration test, which stays unchanged.
 *
 * Modes:
 * - Default: READ-ONLY preview. Prints the exact records. Deletes nothing.
 * - --cleanup --approve=DELETE-ITEST-DATA: deletes, in one transaction.
 *
 * Safety:
 * - Requires DATABASE_URL's host to start with "ep-green-queen-".
 * - Refuses if any real (non-test) invoice is attached to a test store, or if
 *   a test store sits in a governorate that also holds real stores.
 * - Never changes the platform point value. It only reports the current one.
 * - Does not load .env. Run from a terminal where DATABASE_URL is set.
 */
import { PrismaClient } from "@prisma/client";

const REQUIRED_HOST_PREFIX = "ep-green-queen-";
const TEST_PREFIX = "itest-";
const APPROVAL = "DELETE-ITEST-DATA";

function checkStagingHost(): void {
  let host = "";
  try {
    host = new URL(process.env.DATABASE_URL ?? "").hostname;
  } catch {
    throw new Error("DATABASE_URL is missing or not a valid URL.");
  }
  if (!host.startsWith(REQUIRED_HOST_PREFIX)) {
    throw new Error("DATABASE_URL is not the staging database. Nothing was run.");
  }
  console.log("Staging host check passed.");
}

async function main(): Promise<void> {
  checkStagingHost();
  const approved =
    process.argv.includes("--cleanup") &&
    process.argv.includes(`--approve=${APPROVAL}`);

  const prisma = new PrismaClient();
  try {
    const settings = await prisma.platformSettings.findUnique({
      where: { id: 1 },
      select: { pointValueSyp: true },
    });
    console.log(
      `Current point value: ${settings?.pointValueSyp.toString() ?? "(no row)"} SYP. This script does not change it.`,
    );

    // Identify test-owned records by name only.
    const stores = await prisma.store.findMany({
      where: { name: { startsWith: TEST_PREFIX } },
      select: { id: true, name: true, governorateId: true },
    });
    const governorates = await prisma.governorate.findMany({
      where: { nameAr: { startsWith: TEST_PREFIX } },
      select: { id: true, nameAr: true },
    });
    const customers = await prisma.customerProfile.findMany({
      where: { name: { startsWith: TEST_PREFIX } },
      select: { userId: true, name: true },
    });
    const storeIds = stores.map((s) => s.id);
    const govIds = governorates.map((g) => g.id);
    const customerIds = customers.map((c) => c.userId);
    const accounts = await prisma.merchantAccount.findMany({
      where: { storeId: { in: storeIds } },
      select: { id: true, userId: true },
    });
    const merchantUserIds = accounts.map((a) => a.userId);
    const userIds = [...customerIds, ...merchantUserIds];

    // Safety: refuse if real data is attached to any test-owned record.
    const realInvoices = await prisma.loyaltyTransaction.count({
      where: { storeId: { in: storeIds }, customerId: { notIn: customerIds } },
    });
    const realStoresInTestGov = await prisma.store.count({
      where: { governorateId: { in: govIds }, id: { notIn: storeIds } },
    });
    if (realInvoices > 0 || realStoresInTestGov > 0) {
      throw new Error(
        `Refusing cleanup: real data is attached (invoices from non-test customers: ${realInvoices}, real stores in test governorates: ${realStoresInTestGov}).`,
      );
    }

    const counts = {
      governorates: governorates.length,
      stores: stores.length,
      merchantAccounts: accounts.length,
      customers: customers.length,
      invoices: await prisma.loyaltyTransaction.count({ where: { storeId: { in: storeIds } } }),
      merchantSettlements: await prisma.merchantSettlement.count({ where: { storeId: { in: storeIds } } }),
      pointsLedgerEntries: await prisma.pointsLedgerEntry.count({ where: { customerId: { in: customerIds } } }),
      cashRequests: await prisma.cashRedemptionRequest.count({ where: { customerId: { in: customerIds } } }),
      productRedemptions: await prisma.productRedemption.count({ where: { customerId: { in: customerIds } } }),
      shareRewardClaims: await prisma.shareRewardClaim.count({ where: { customerId: { in: customerIds } } }),
      deviceTokens: await prisma.deviceToken.count({ where: { userId: { in: userIds } } }),
    };

    console.log("Test-owned records (name starts with itest-):");
    for (const g of governorates) console.log(`  governorate: ${g.nameAr}`);
    for (const s of stores) console.log(`  store: ${s.name}`);
    for (const c of customers) console.log(`  customer: ${c.name}`);
    console.log("Related rows:", JSON.stringify(counts));

    if (!approved) {
      console.log("PREVIEW ONLY. Nothing was deleted.");
      console.log(`To delete, run with: --cleanup --approve=${APPROVAL}`);
      return;
    }
    if (governorates.length + stores.length + customers.length === 0) {
      console.log("Nothing to clean up.");
      return;
    }

    // Dependency order, all in one transaction: all or nothing.
    await prisma.$transaction([
      prisma.pointsLedgerEntry.deleteMany({ where: { customerId: { in: customerIds } } }),
      prisma.shareRewardClaim.deleteMany({ where: { customerId: { in: customerIds } } }),
      prisma.cashRedemptionRequest.deleteMany({ where: { customerId: { in: customerIds } } }),
      prisma.productRedemption.deleteMany({ where: { customerId: { in: customerIds } } }),
      prisma.deviceToken.deleteMany({ where: { userId: { in: userIds } } }),
      prisma.merchantSettlement.deleteMany({ where: { storeId: { in: storeIds } } }),
      prisma.loyaltyTransaction.deleteMany({ where: { storeId: { in: storeIds } } }),
      prisma.merchantAccount.deleteMany({ where: { storeId: { in: storeIds } } }),
      prisma.customerProfile.deleteMany({ where: { userId: { in: customerIds } } }),
      prisma.user.deleteMany({ where: { id: { in: userIds } } }),
      prisma.store.deleteMany({ where: { id: { in: storeIds } } }),
      prisma.governorate.deleteMany({ where: { id: { in: govIds } } }),
    ]);
    console.log("Cleanup committed. Point value was not changed.");
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((error: unknown) => {
  console.error("CLEANUP FAILED: nothing was partially deleted.");
  console.error(error instanceof Error ? (error.stack ?? error.message) : String(error));
  process.exit(1);
});
