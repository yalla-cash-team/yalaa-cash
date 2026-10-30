-- Banner image uploads: bytes live in BannerImage; Banner keeps a version
-- counter for cache-busting. Existing banners keep their imageUrl.

ALTER TABLE "Banner" ADD COLUMN "imageVersion" INTEGER NOT NULL DEFAULT 0;

CREATE TABLE "BannerImage" (
    "bannerId" UUID NOT NULL,
    "contentType" TEXT NOT NULL,
    "data" BYTEA NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "BannerImage_pkey" PRIMARY KEY ("bannerId")
);

ALTER TABLE "BannerImage" ADD CONSTRAINT "BannerImage_bannerId_fkey"
    FOREIGN KEY ("bannerId") REFERENCES "Banner"("id") ON DELETE CASCADE ON UPDATE CASCADE;
