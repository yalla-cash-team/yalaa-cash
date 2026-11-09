/**
 * Read-only pre-release audit of stores against the city hierarchy.
 *
 *   pnpm audit:cities [--json]
 *
 * Uses DATABASE_URL. Run it BEFORE and AFTER the city migration. Everything
 * runs inside ONE transaction that is switched to READ ONLY first, so the
 * database itself rejects any write (SQLSTATE 25006) even if this file were
 * ever edited by mistake. Nothing is written, merged or deleted, there is no
 * network access other than the database, and the connection string and host
 * are never printed. Exit code 1 = blockers found, 2 = audit could not run.
 */
import { PrismaClient } from "@prisma/client";
import {
  AuditCity,
  AuditStore,
  auditStores,
  formatAuditReport,
} from "../src/admin/city-audit";

async function main() {
  const prisma = new PrismaClient({ log: [] });
  try {
    const report = await prisma.$transaction(
      async (tx) => {
        // Must be the first statement of the transaction.
        await tx.$executeRawUnsafe("SET TRANSACTION READ ONLY");

        const [{ exists }] = await tx.$queryRaw<{ exists: boolean }[]>`
          SELECT to_regclass('public."City"') IS NOT NULL AS exists`;
        const hasCityTable = exists === true;
        const [{ n }] = await tx.$queryRaw<{ n: bigint }[]>`
          SELECT count(*) AS n FROM information_schema.columns
          WHERE table_name = 'Store' AND column_name IN ('cityId', 'displayOrder')`;
        const hasCityColumns = hasCityTable && Number(n) === 2;

        const stores = hasCityColumns
          ? await tx.$queryRaw<AuditStore[]>`
              SELECT id::text, name, category, city, "cityId"::text AS "cityId",
                     "governorateId"::text AS "governorateId", "isActive", "displayOrder"
              FROM "Store"`
          : await tx.$queryRaw<AuditStore[]>`
              SELECT id::text, name, category, city,
                     "governorateId"::text AS "governorateId", "isActive"
              FROM "Store"`;
        const cities = hasCityColumns
          ? await tx.$queryRaw<AuditCity[]>`
              SELECT id::text, "governorateId"::text AS "governorateId", "nameAr", "isActive"
              FROM "City"`
          : [];
        return auditStores(stores, cities, hasCityColumns);
      },
      { timeout: 60_000 },
    );

    console.log(formatAuditReport(report));
    if (process.argv.includes("--json")) {
      console.log(JSON.stringify(report, null, 2));
    }
    process.exitCode = report.releaseSafe ? 0 : 1;
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((e) => {
  // Never echo e.message: driver errors can contain connection details.
  const code = (e as { code?: string })?.code ?? (e as Error)?.name ?? "error";
  console.error(`City audit could not run (${code}).`);
  process.exit(2);
});
