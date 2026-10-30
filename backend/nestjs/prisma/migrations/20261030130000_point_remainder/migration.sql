-- Fractional SYP left over after converting an earning into whole points.
-- Existing customers start with a zero remainder, so no balances change.

ALTER TABLE "CustomerProfile"
  ADD COLUMN "pointRemainderSyp" DECIMAL(12,4) NOT NULL DEFAULT 0;
