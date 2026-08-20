-- Paesi attesi e SKU esclusi per gli avvisi di copertura listing Amazon.
-- Solo schema product.

CREATE TABLE IF NOT EXISTS "product"."AmazonListingCoverageSetting" (
    "id" TEXT NOT NULL,
    "expectedMarketplaceIds" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    "excludeParentSkus" BOOLEAN NOT NULL DEFAULT true,
    "includeFba" BOOLEAN NOT NULL DEFAULT true,
    "includeFbm" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AmazonListingCoverageSetting_pkey" PRIMARY KEY ("id")
);

INSERT INTO "product"."AmazonListingCoverageSetting" (
    "id",
    "expectedMarketplaceIds",
    "excludeParentSkus",
    "includeFba",
    "includeFbm",
    "createdAt",
    "updatedAt"
)
VALUES ('default', ARRAY[]::TEXT[], true, true, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
ON CONFLICT ("id") DO NOTHING;

CREATE TABLE IF NOT EXISTS "product"."AmazonListingCoverageSkuExclusion" (
    "id" TEXT NOT NULL,
    "sku" TEXT NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AmazonListingCoverageSkuExclusion_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "AmazonListingCoverageSkuExclusion_sku"
    ON "product"."AmazonListingCoverageSkuExclusion" ("sku");
