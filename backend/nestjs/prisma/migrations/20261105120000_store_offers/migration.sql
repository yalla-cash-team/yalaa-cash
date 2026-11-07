-- Exclusive store offers (view-only). Purely additive: two new tables, one
-- index and their foreign keys. No existing table, column or row is changed,
-- so stores, the exclusive city/category rule, balances, accounts and
-- transactions are untouched, and backends that predate this migration keep
-- working against it.
--
-- Availability window, stored as UTC instants computed from Asia/Damascus
-- calendar dates:
--   "startsAt"   inclusive: 00:00 Damascus time of the first selected day.
--   "endsBefore" EXCLUSIVE: 00:00 Damascus time of the day after the last
--                selected day, so the whole last day is included without
--                end-of-day precision edge cases.
-- Available when "isActive", the store is active, and
--   ("startsAt" IS NULL OR "startsAt" <= now) AND ("endsBefore" IS NULL OR now < "endsBefore").
-- Offer images use the same storage pattern as StoreLogo and BannerImage.

CREATE TABLE "StoreOffer" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "storeId" UUID NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT NOT NULL DEFAULT '',
    "discountLabel" TEXT,
    "imageVersion" INTEGER NOT NULL DEFAULT 0,
    "startsAt" TIMESTAMP(3),
    "endsBefore" TIMESTAMP(3),
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "displayOrder" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "StoreOffer_pkey" PRIMARY KEY ("id"),
    -- Defence in depth for the API's own validation: the exclusive end
    -- boundary must come after the start. Prisma does not model CHECK
    -- constraints; it neither creates nor removes them, so this stays as is.
    CONSTRAINT "StoreOffer_window_check" CHECK (
        "startsAt" IS NULL OR "endsBefore" IS NULL OR "endsBefore" > "startsAt"
    )
);

CREATE TABLE "StoreOfferImage" (
    "offerId" UUID NOT NULL,
    "contentType" TEXT NOT NULL,
    "data" BYTEA NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "StoreOfferImage_pkey" PRIMARY KEY ("offerId")
);

-- Serves "offers of this store", filtered by isActive and ordered for display.
CREATE INDEX "StoreOffer_storeId_isActive_displayOrder_idx"
    ON "StoreOffer"("storeId", "isActive", "displayOrder");

-- Offers belong to a store. Stores are only ever soft-deleted (isActive=false)
-- by the API; the cascade only applies if a store row is ever hard-deleted.
ALTER TABLE "StoreOffer" ADD CONSTRAINT "StoreOffer_storeId_fkey"
    FOREIGN KEY ("storeId") REFERENCES "Store"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "StoreOfferImage" ADD CONSTRAINT "StoreOfferImage_offerId_fkey"
    FOREIGN KEY ("offerId") REFERENCES "StoreOffer"("id") ON DELETE CASCADE ON UPDATE CASCADE;
