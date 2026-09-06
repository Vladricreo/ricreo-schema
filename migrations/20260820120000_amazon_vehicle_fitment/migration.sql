-- Catalogo veicoli Amazon (KTYPE) e stato fitment per listing.
-- Solo schema product.

CREATE TABLE IF NOT EXISTS "product"."AmazonVehicle" (
    "id" TEXT NOT NULL,
    "marketplaceId" TEXT NOT NULL,
    "vehicleType" TEXT NOT NULL,
    "identifier" TEXT NOT NULL,
    "make" TEXT NOT NULL,
    "model" TEXT NOT NULL,
    "variantName" TEXT,
    "bodyStyle" TEXT,
    "driveType" TEXT,
    "energy" TEXT,
    "engineKw" DECIMAL(10,2),
    "engineHp" DECIMAL(10,2),
    "yearFrom" INTEGER,
    "monthFrom" INTEGER,
    "yearTo" INTEGER,
    "monthTo" INTEGER,
    "status" TEXT NOT NULL DEFAULT 'ACTIVE',
    "ktype" TEXT,
    "amazonId" TEXT,
    "lastProcessedAt" TIMESTAMPTZ(6),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AmazonVehicle_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "AmazonVehicle_ident_key"
    ON "product"."AmazonVehicle" ("marketplaceId", "vehicleType", "identifier");
CREATE INDEX IF NOT EXISTS "AmazonVehicle_make_model"
    ON "product"."AmazonVehicle" ("marketplaceId", "make", "model");
CREATE INDEX IF NOT EXISTS "AmazonVehicle_ktype"
    ON "product"."AmazonVehicle" ("marketplaceId", "ktype");
CREATE INDEX IF NOT EXISTS "AmazonVehicle_status"
    ON "product"."AmazonVehicle" ("marketplaceId", "status");

CREATE TABLE IF NOT EXISTS "product"."AmazonVehicleSyncJob" (
    "id" TEXT NOT NULL,
    "marketplaceId" TEXT NOT NULL,
    "phase" TEXT NOT NULL DEFAULT 'CAR',
    "pageToken" TEXT,
    "processed" INTEGER NOT NULL DEFAULT 0,
    "upserted" INTEGER NOT NULL DEFAULT 0,
    "status" "product"."StoreReportStatus" NOT NULL DEFAULT 'REQUESTED',
    "lastMessage" TEXT,
    "errorMessage" TEXT,
    "importedAt" TIMESTAMPTZ(6),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AmazonVehicleSyncJob_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "AmazonVehicleSyncJob_marketplace"
    ON "product"."AmazonVehicleSyncJob" ("marketplaceId");
CREATE INDEX IF NOT EXISTS "AmazonVehicleSyncJob_status"
    ON "product"."AmazonVehicleSyncJob" ("status", "updatedAt");

CREATE TABLE IF NOT EXISTS "product"."AmazonListingFitment" (
    "id" TEXT NOT NULL,
    "marketplaceId" TEXT NOT NULL,
    "sku" TEXT NOT NULL,
    "asin" TEXT,
    "publishedKtypes" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "publishedCount" INTEGER NOT NULL DEFAULT 0,
    "lastResearch" JSONB,
    "lastResearchedAt" TIMESTAMPTZ(6),
    "lastPublishedAt" TIMESTAMPTZ(6),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AmazonListingFitment_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "AmazonListingFitment_sku_key"
    ON "product"."AmazonListingFitment" ("marketplaceId", "sku");
CREATE INDEX IF NOT EXISTS "AmazonListingFitment_count"
    ON "product"."AmazonListingFitment" ("marketplaceId", "publishedCount");
