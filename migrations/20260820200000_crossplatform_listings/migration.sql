-- Hub crossplatform: presenza SKU, regole prezzo, ignore list, default pubblicazione.
-- Solo schema product.

ALTER TABLE "product"."TemuGoodsMapping"
ADD COLUMN IF NOT EXISTS "temuSkuId" TEXT;

DO $$ BEGIN
    CREATE TYPE "product"."CrossplatformPriceAdjustmentType" AS ENUM ('PERCENT', 'FIXED');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

CREATE TABLE IF NOT EXISTS "product"."CrossplatformListingLink" (
    "id" TEXT NOT NULL,
    "sku" TEXT NOT NULL,
    "channel" "product"."StoreChannel" NOT NULL,
    "storeKey" TEXT NOT NULL,
    "countryCode" TEXT,
    "externalId" TEXT NOT NULL,
    "temuSkuId" TEXT,
    "title" TEXT NOT NULL DEFAULT '',
    "imageUrl" TEXT,
    "price" DECIMAL(12,2),
    "currency" TEXT,
    "status" TEXT,
    "lastSyncedAt" TIMESTAMPTZ(6) NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CrossplatformListingLink_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "CrossplatformListingLink_sku_store"
ON "product"."CrossplatformListingLink"("sku", "channel", "storeKey");

CREATE INDEX IF NOT EXISTS "CrossplatformListingLink_channel"
ON "product"."CrossplatformListingLink"("channel", "storeKey");

CREATE INDEX IF NOT EXISTS "CrossplatformListingLink_sku"
ON "product"."CrossplatformListingLink"("sku");

CREATE TABLE IF NOT EXISTS "product"."CrossplatformPriceRule" (
    "id" TEXT NOT NULL,
    "targetChannel" "product"."StoreChannel" NOT NULL,
    "adjustmentType" "product"."CrossplatformPriceAdjustmentType" NOT NULL,
    "adjustmentValue" DECIMAL(12,4) NOT NULL,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CrossplatformPriceRule_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "CrossplatformPriceRule_channel"
ON "product"."CrossplatformPriceRule"("targetChannel");

INSERT INTO "product"."CrossplatformPriceRule" (
    "id", "targetChannel", "adjustmentType", "adjustmentValue", "isActive", "createdAt", "updatedAt"
)
VALUES
    ('ebay-default', 'EBAY', 'PERCENT', -20, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('etsy-default', 'ETSY', 'PERCENT', 0, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
    ('temu-default', 'TEMU', 'PERCENT', 0, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
ON CONFLICT ("targetChannel") DO NOTHING;

CREATE TABLE IF NOT EXISTS "product"."CrossplatformIgnoredSku" (
    "id" TEXT NOT NULL,
    "sku" TEXT NOT NULL,
    "reason" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CrossplatformIgnoredSku_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "CrossplatformIgnoredSku_sku"
ON "product"."CrossplatformIgnoredSku"("sku");

CREATE TABLE IF NOT EXISTS "product"."CrossplatformPublishDefaults" (
    "id" TEXT NOT NULL,
    "ebaySite" TEXT NOT NULL DEFAULT 'Italy',
    "ebayCategoryId" TEXT NOT NULL DEFAULT '',
    "ebayConditionId" TEXT NOT NULL DEFAULT '1000',
    "ebayPostalCode" TEXT NOT NULL DEFAULT '',
    "ebayCountry" TEXT NOT NULL DEFAULT 'IT',
    "ebayCurrency" TEXT NOT NULL DEFAULT 'EUR',
    "ebayDispatchTimeMax" INTEGER NOT NULL DEFAULT 3,
    "ebayReturnsAccepted" BOOLEAN NOT NULL DEFAULT true,
    "ebayReturnsWithin" TEXT NOT NULL DEFAULT 'Days_30',
    "ebayShippingCost" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "ebayShippingService" TEXT NOT NULL DEFAULT 'IT_PriorityShipping',
    "ebayVatPercent" DECIMAL(5,2) NOT NULL DEFAULT 22,
    "etsyWhoMade" TEXT NOT NULL DEFAULT 'someone_else',
    "etsyWhenMade" TEXT NOT NULL DEFAULT 'made_to_order',
    "etsyTaxonomyId" INTEGER,
    "etsyShippingProfileId" INTEGER,
    "etsyReadinessStateId" INTEGER,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CrossplatformPublishDefaults_pkey" PRIMARY KEY ("id")
);

INSERT INTO "product"."CrossplatformPublishDefaults" ("id", "createdAt", "updatedAt")
VALUES ('default', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
ON CONFLICT ("id") DO NOTHING;

CREATE TABLE IF NOT EXISTS "product"."CrossplatformSyncJob" (
    "id" TEXT NOT NULL,
    "phase" TEXT NOT NULL DEFAULT 'amazon',
    "pageToken" TEXT,
    "offset" INTEGER NOT NULL DEFAULT 0,
    "processed" INTEGER NOT NULL DEFAULT 0,
    "upserted" INTEGER NOT NULL DEFAULT 0,
    "status" "product"."StoreReportStatus" NOT NULL DEFAULT 'REQUESTED',
    "lastMessage" TEXT,
    "errorMessage" TEXT,
    "importedAt" TIMESTAMPTZ(6),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CrossplatformSyncJob_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "CrossplatformSyncJob_status"
ON "product"."CrossplatformSyncJob"("status", "updatedAt");
