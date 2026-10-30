-- Share-app reward: a configurable number of points granted once per customer.
-- Defaults to 0 (disabled). Existing customers have no claim yet.

ALTER TYPE "PointsEntryType" ADD VALUE 'SHARE_REWARD';

ALTER TABLE "PlatformSettings"
  ADD COLUMN "shareRewardPoints" BIGINT NOT NULL DEFAULT 0;

CREATE TABLE "ShareRewardClaim" (
    "customerId" UUID NOT NULL,
    "pointsAwarded" BIGINT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ShareRewardClaim_pkey" PRIMARY KEY ("customerId")
);

ALTER TABLE "ShareRewardClaim" ADD CONSTRAINT "ShareRewardClaim_customerId_fkey"
    FOREIGN KEY ("customerId") REFERENCES "CustomerProfile"("userId") ON DELETE CASCADE ON UPDATE CASCADE;
