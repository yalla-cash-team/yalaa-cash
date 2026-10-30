-- Digital product images: bytes live in their own table; DigitalProduct keeps
-- a version counter for cache-busting. Existing products keep their imageUrl.

ALTER TABLE "DigitalProduct" ADD COLUMN "imageVersion" INTEGER NOT NULL DEFAULT 0;

CREATE TABLE "DigitalProductImage" (
    "productId" UUID NOT NULL,
    "contentType" TEXT NOT NULL,
    "data" BYTEA NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "DigitalProductImage_pkey" PRIMARY KEY ("productId")
);

ALTER TABLE "DigitalProductImage" ADD CONSTRAINT "DigitalProductImage_productId_fkey"
    FOREIGN KEY ("productId") REFERENCES "DigitalProduct"("id") ON DELETE CASCADE ON UPDATE CASCADE;
