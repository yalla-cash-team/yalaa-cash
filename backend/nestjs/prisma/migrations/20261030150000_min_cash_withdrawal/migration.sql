-- Configurable minimum cash withdrawal (SYP). Stored only for now; existing
-- redemption behavior is unchanged. Defaults to 0 (no minimum).

ALTER TABLE "PlatformSettings"
  ADD COLUMN "minCashWithdrawalSyp" BIGINT NOT NULL DEFAULT 0;
