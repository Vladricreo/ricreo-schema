-- Ledger FBA giornaliero (Reports GET_LEDGER_SUMMARY_VIEW_DATA).
-- Solo schema product.

CREATE TABLE IF NOT EXISTS "product"."StoreFbaInventoryDaily" (
    "id" TEXT NOT NULL,
    "channel" "product"."StoreChannel" NOT NULL,
    "storeKey" TEXT NOT NULL,
    "date" DATE NOT NULL,
    "fnsku" TEXT NOT NULL,
    "asin" TEXT NOT NULL,
    "msku" TEXT NOT NULL,
    "title" TEXT NOT NULL DEFAULT '',
    "disposition" TEXT NOT NULL,
    "location" TEXT NOT NULL,
    "startingWarehouseBalance" INTEGER NOT NULL DEFAULT 0,
    "inTransitBetweenWarehouses" INTEGER NOT NULL DEFAULT 0,
    "receipts" INTEGER NOT NULL DEFAULT 0,
    "customerShipments" INTEGER NOT NULL DEFAULT 0,
    "customerReturns" INTEGER NOT NULL DEFAULT 0,
    "vendorReturns" INTEGER NOT NULL DEFAULT 0,
    "warehouseTransferInOut" INTEGER NOT NULL DEFAULT 0,
    "found" INTEGER NOT NULL DEFAULT 0,
    "lost" INTEGER NOT NULL DEFAULT 0,
    "damaged" INTEGER NOT NULL DEFAULT 0,
    "disposed" INTEGER NOT NULL DEFAULT 0,
    "otherEvents" INTEGER NOT NULL DEFAULT 0,
    "endingWarehouseBalance" INTEGER NOT NULL DEFAULT 0,
    "unknownEvents" INTEGER NOT NULL DEFAULT 0,
    "extra" JSONB,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "StoreFbaInventoryDaily_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "StoreFbaInventoryDaily_grain"
ON "product"."StoreFbaInventoryDaily" ("channel", "date", "fnsku", "disposition", "location");

CREATE INDEX IF NOT EXISTS "StoreFbaInventoryDaily_asin_date_idx"
ON "product"."StoreFbaInventoryDaily" ("asin", "date");

CREATE INDEX IF NOT EXISTS "StoreFbaInventoryDaily_msku_date_idx"
ON "product"."StoreFbaInventoryDaily" ("msku", "date");

CREATE INDEX IF NOT EXISTS "StoreFbaInventoryDaily_endingWarehouseBalance_idx"
ON "product"."StoreFbaInventoryDaily" ("endingWarehouseBalance");

CREATE INDEX IF NOT EXISTS "StoreFbaInventoryDaily_channel_storeKey_date_idx"
ON "product"."StoreFbaInventoryDaily" ("channel", "storeKey", "date");
