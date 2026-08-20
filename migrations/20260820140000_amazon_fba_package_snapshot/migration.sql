-- Snapshot dimensioni/peso pacco FBA Amazon + job di sync.
-- Solo schema product.

CREATE TABLE IF NOT EXISTS "product"."AmazonFbaPackageSnapshot" (
    "id" TEXT NOT NULL,
    "marketplaceId" TEXT NOT NULL,
    "sku" TEXT NOT NULL,
    "asin" TEXT,
    "productType" TEXT,
    "title" TEXT,
    "imageUrl" TEXT,
    "catalogLengthCm" DECIMAL(12,2),
    "catalogWidthCm" DECIMAL(12,2),
    "catalogHeightCm" DECIMAL(12,2),
    "catalogWeightG" DECIMAL(12,2),
    "listingLengthCm" DECIMAL(12,2),
    "listingWidthCm" DECIMAL(12,2),
    "listingHeightCm" DECIMAL(12,2),
    "listingWeightG" DECIMAL(12,2),
    "fetchedAt" TIMESTAMPTZ(6) NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AmazonFbaPackageSnapshot_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "AmazonFbaPackageSnapshot_sku_key"
    ON "product"."AmazonFbaPackageSnapshot" ("marketplaceId", "sku");

CREATE INDEX IF NOT EXISTS "AmazonFbaPackageSnapshot_asin"
    ON "product"."AmazonFbaPackageSnapshot" ("marketplaceId", "asin");

CREATE INDEX IF NOT EXISTS "AmazonFbaPackageSnapshot_fetched"
    ON "product"."AmazonFbaPackageSnapshot" ("marketplaceId", "fetchedAt");

CREATE TABLE IF NOT EXISTS "product"."AmazonFbaPackageSyncJob" (
    "id" TEXT NOT NULL,
    "marketplaceId" TEXT NOT NULL,
    "cursor" INTEGER NOT NULL DEFAULT 0,
    "processed" INTEGER NOT NULL DEFAULT 0,
    "total" INTEGER NOT NULL DEFAULT 0,
    "status" "product"."StoreReportStatus" NOT NULL DEFAULT 'REQUESTED',
    "lastMessage" TEXT,
    "importedAt" TIMESTAMPTZ(6),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AmazonFbaPackageSyncJob_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "AmazonFbaPackageSyncJob_marketplace"
    ON "product"."AmazonFbaPackageSyncJob" ("marketplaceId");

CREATE INDEX IF NOT EXISTS "AmazonFbaPackageSyncJob_status"
    ON "product"."AmazonFbaPackageSyncJob" ("status", "updatedAt");
