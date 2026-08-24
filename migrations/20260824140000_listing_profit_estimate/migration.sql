-- Snapshot commissioni/prezzo listing e job import pagina Profitto.
-- Solo schema product.

CREATE TABLE IF NOT EXISTS "product"."ListingProfitEstimate" (
    "id" TEXT NOT NULL,
    "channel" "product"."StoreChannel" NOT NULL,
    "storeKey" TEXT NOT NULL,
    "countryCode" VARCHAR(2) NOT NULL,
    "sku" TEXT NOT NULL,
    "asin" TEXT,
    "fulfillment" TEXT,
    "listingPrice" DECIMAL(12,2),
    "customerShipping" DECIMAL(12,2),
    "currency" VARCHAR(3) NOT NULL DEFAULT 'EUR',
    "referralFee" DECIMAL(12,4),
    "digitalServicesFee" DECIMAL(12,4),
    "fbaFee" DECIMAL(12,4),
    "importedAt" TIMESTAMPTZ(6) NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ListingProfitEstimate_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "ListingProfitEstimate_sku_store"
    ON "product"."ListingProfitEstimate"("channel", "storeKey", "sku");

CREATE INDEX IF NOT EXISTS "ListingProfitEstimate_sku"
    ON "product"."ListingProfitEstimate"("sku");

CREATE INDEX IF NOT EXISTS "ListingProfitEstimate_channel_sku"
    ON "product"."ListingProfitEstimate"("channel", "sku");

CREATE TABLE IF NOT EXISTS "product"."ListingProfitImportJob" (
    "id" TEXT NOT NULL,
    "channel" "product"."StoreChannel" NOT NULL,
    "capturedAt" DATE NOT NULL,
    "marketplaceIndex" INTEGER NOT NULL DEFAULT 0,
    "nextAmazonPage" INTEGER NOT NULL DEFAULT 1,
    "extraOffset" INTEGER NOT NULL DEFAULT 0,
    "phase" TEXT NOT NULL DEFAULT 'listings',
    "processed" INTEGER NOT NULL DEFAULT 0,
    "total" INTEGER NOT NULL DEFAULT 0,
    "status" "product"."StoreReportStatus" NOT NULL DEFAULT 'REQUESTED',
    "lastMessage" TEXT,
    "errorMessage" TEXT,
    "importedAt" TIMESTAMPTZ(6),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ListingProfitImportJob_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "ListingProfitImportJob_day"
    ON "product"."ListingProfitImportJob"("channel", "capturedAt");

CREATE INDEX IF NOT EXISTS "ListingProfitImportJob_status"
    ON "product"."ListingProfitImportJob"("status", "updatedAt");
