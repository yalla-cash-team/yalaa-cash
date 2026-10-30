-- Store logos: image bytes live in their own table, and Store tracks a
-- version counter used to cache-bust the logo URL. Existing stores have no
-- logo until an admin uploads one.

ALTER TABLE "Store" ADD COLUMN "logoVersion" INTEGER NOT NULL DEFAULT 0;

CREATE TABLE "StoreLogo" (
    "storeId" UUID NOT NULL,
    "contentType" TEXT NOT NULL,
    "data" BYTEA NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "StoreLogo_pkey" PRIMARY KEY ("storeId")
);

ALTER TABLE "StoreLogo" ADD CONSTRAINT "StoreLogo_storeId_fkey"
    FOREIGN KEY ("storeId") REFERENCES "Store"("id") ON DELETE CASCADE ON UPDATE CASCADE;
