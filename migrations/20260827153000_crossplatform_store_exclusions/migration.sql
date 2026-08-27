-- Esclusioni store hub crossplatform: globali e per SKU.
-- Solo schema product.

CREATE TABLE IF NOT EXISTS "product"."CrossplatformExcludedStore" (
    "id" TEXT NOT NULL,
    "channel" "product"."StoreChannel" NOT NULL,
    "reason" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CrossplatformExcludedStore_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "CrossplatformExcludedStore_channel"
ON "product"."CrossplatformExcludedStore"("channel");

CREATE TABLE IF NOT EXISTS "product"."CrossplatformSkuStoreExclusion" (
    "id" TEXT NOT NULL,
    "sku" TEXT NOT NULL,
    "channel" "product"."StoreChannel" NOT NULL,
    "reason" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CrossplatformSkuStoreExclusion_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "CrossplatformSkuStoreExclusion_sku_channel"
ON "product"."CrossplatformSkuStoreExclusion"("sku", "channel");

CREATE INDEX IF NOT EXISTS "CrossplatformSkuStoreExclusion_sku"
ON "product"."CrossplatformSkuStoreExclusion"("sku");
