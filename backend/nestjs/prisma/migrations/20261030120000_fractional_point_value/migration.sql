-- Point values may now be fractional (e.g. 0.10 SYP per point).
-- INTEGER -> NUMERIC(12,4) is lossless, so existing rows keep their values.

ALTER TABLE "PlatformSettings"
  ALTER COLUMN "pointValueSyp" TYPE DECIMAL(12,4) USING "pointValueSyp"::DECIMAL(12,4);

ALTER TABLE "LoyaltyTransaction"
  ALTER COLUMN "pointValueSypSnapshot" TYPE DECIMAL(12,4) USING "pointValueSypSnapshot"::DECIMAL(12,4);

ALTER TABLE "CashRedemptionRequest"
  ALTER COLUMN "pointValueSypSnapshot" TYPE DECIMAL(12,4) USING "pointValueSypSnapshot"::DECIMAL(12,4);
