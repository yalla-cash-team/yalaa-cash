-- Additive: City table, Store.cityId/displayOrder, CustomerProfile.cityId.
-- No existing column is altered or dropped; Store.city (text) is kept.

CREATE TABLE "City" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "governorateId" UUID NOT NULL,
    "nameAr" TEXT NOT NULL,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "displayOrder" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "City_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "City_governorateId_nameAr_key" ON "City"("governorateId", "nameAr");
CREATE INDEX "City_governorateId_isActive_displayOrder_idx" ON "City"("governorateId", "isActive", "displayOrder");

ALTER TABLE "City" ADD CONSTRAINT "City_governorateId_fkey"
    FOREIGN KEY ("governorateId") REFERENCES "Governorate"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "Store" ADD COLUMN "cityId" UUID;
ALTER TABLE "Store" ADD COLUMN "displayOrder" INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "CustomerProfile" ADD COLUMN "cityId" UUID;

ALTER TABLE "Store" ADD CONSTRAINT "Store_cityId_fkey"
    FOREIGN KEY ("cityId") REFERENCES "City"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "CustomerProfile" ADD CONSTRAINT "CustomerProfile_cityId_fkey"
    FOREIGN KEY ("cityId") REFERENCES "City"("id") ON DELETE SET NULL ON UPDATE CASCADE;

CREATE INDEX "Store_cityId_isActive_displayOrder_idx" ON "Store"("cityId", "isActive", "displayOrder");
CREATE INDEX "CustomerProfile_cityId_idx" ON "CustomerProfile"("cityId");

-- Backfill cities from the exact existing (governorate, city name) pairs.
-- Names are compared after trimming and collapsing whitespace and ignoring
-- case ONLY. Spelling variants (e.g. Latin vs Arabic, alef/taa-marbuta forms)
-- stay separate cities and are NOT merged or guessed: the pre-release audit
-- (scripts/city-audit.ts) lists them for manual correction. Stores with a
-- blank city keep cityId NULL and are reported by the audit as well.
INSERT INTO "City" ("governorateId", "nameAr", "updatedAt")
SELECT "governorateId",
       MIN(btrim(regexp_replace("city", '\s+', ' ', 'g'))),
       CURRENT_TIMESTAMP
FROM "Store"
WHERE btrim("city") <> ''
GROUP BY "governorateId", lower(btrim(regexp_replace("city", '\s+', ' ', 'g')));

UPDATE "Store" s SET "cityId" = c."id"
FROM "City" c
WHERE c."governorateId" = s."governorateId"
  AND lower(c."nameAr") = lower(btrim(regexp_replace(s."city", '\s+', ' ', 'g')));

-- Initial positions keep today's list order (category, name) per city.
UPDATE "Store" s SET "displayOrder" = r.pos
FROM (
    SELECT "id", ROW_NUMBER() OVER (
        PARTITION BY "cityId" ORDER BY "category", "name", "id") AS pos
    FROM "Store"
    WHERE "isActive" = true AND "cityId" IS NOT NULL
) r
WHERE s."id" = r."id";

-- One active store per city and category, now keyed on the CITY (id), so the
-- same city name in two governorates no longer collides. The old index used
-- the free-text city name only. Stores without a city (unmatched legacy rows)
-- keep an equivalent guard, scoped to their governorate.
-- NOTE: creating these unique indexes fails if two active stores of the same
-- category map to the SAME city (e.g. names differing only by spacing/case).
-- Run `pnpm audit:cities` first: EXCLUSIVITY_CONFLICT lists exactly those rows.
DROP INDEX IF EXISTS "Store_one_active_category_per_city_key";

CREATE UNIQUE INDEX "Store_one_active_category_per_city_id_key"
    ON "Store" ("cityId", lower("category"))
    WHERE "isActive" = true AND "cityId" IS NOT NULL;

CREATE UNIQUE INDEX "Store_one_active_category_per_legacy_city_key"
    ON "Store" ("governorateId", lower("city"), lower("category"))
    WHERE "isActive" = true AND "cityId" IS NULL;
