-- Ledger entries written when the admin changes the point value and existing
-- balances are converted to keep their monetary amount.

ALTER TYPE "PointsEntryType" ADD VALUE 'POINT_CONVERSION';
