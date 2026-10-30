-- Monthly merchant settlements. Existing rows become CYCLE, so the per-merchant
-- cycle behaviour is unchanged. Rows are never rewritten.

CREATE TYPE "SettlementKind" AS ENUM ('CYCLE', 'MONTHLY');

ALTER TABLE "MerchantSettlement"
  ADD COLUMN "kind" "SettlementKind" NOT NULL DEFAULT 'CYCLE';
