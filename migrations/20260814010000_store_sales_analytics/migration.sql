-- Analytics vendite multi-store nello schema product (Amazon ora; Etsy/eBay/Temu dopo).
-- Non tocca inventory.

CREATE TYPE "product"."StoreChannel" AS ENUM ('AMAZON', 'ETSY', 'EBAY', 'TEMU');

CREATE TYPE "product"."StoreReportStatus" AS ENUM ('REQUESTED', 'DONE', 'FAILED', 'CANCELLED');

CREATE TABLE "product"."StoreSalesDaily" (
    "id" TEXT NOT NULL,
    "channel" "product"."StoreChannel" NOT NULL,
    "storeKey" TEXT NOT NULL,
    "sku" TEXT NOT NULL,
    "date" DATE NOT NULL,
    "asin" TEXT,
    "productName" TEXT,
    "unitsOrdered" INTEGER NOT NULL DEFAULT 0,
    "unitsRefunded" INTEGER NOT NULL DEFAULT 0,
    "unitsShipped" INTEGER NOT NULL DEFAULT 0,
    "orderedProductSales" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "currency" TEXT NOT NULL DEFAULT 'EUR',
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "StoreSalesDaily_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "StoreSalesDaily_channel_storeKey_sku_date_key"
    ON "product"."StoreSalesDaily"("channel", "storeKey", "sku", "date");
CREATE INDEX "StoreSalesDaily_sku_date_idx" ON "product"."StoreSalesDaily"("sku", "date");
CREATE INDEX "StoreSalesDaily_channel_date_idx" ON "product"."StoreSalesDaily"("channel", "date");

CREATE TABLE "product"."StoreOrderLine" (
    "id" TEXT NOT NULL,
    "channel" "product"."StoreChannel" NOT NULL,
    "storeKey" TEXT NOT NULL,
    "lineKey" TEXT NOT NULL,
    "amazonOrderId" TEXT,
    "orderItemId" TEXT,
    "purchaseDate" TIMESTAMPTZ(6),
    "fulfillmentChannel" TEXT,
    "salesChannel" TEXT,
    "shipCountry" TEXT,
    "sku" TEXT NOT NULL,
    "asin" TEXT,
    "productName" TEXT,
    "quantity" INTEGER NOT NULL DEFAULT 0,
    "itemPrice" DECIMAL(12,2),
    "itemStatus" TEXT,
    "currency" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "StoreOrderLine_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "StoreOrderLine_channel_lineKey_key"
    ON "product"."StoreOrderLine"("channel", "lineKey");
CREATE INDEX "StoreOrderLine_sku_purchaseDate_idx"
    ON "product"."StoreOrderLine"("sku", "purchaseDate");
CREATE INDEX "StoreOrderLine_storeKey_purchaseDate_idx"
    ON "product"."StoreOrderLine"("storeKey", "purchaseDate");
CREATE INDEX "StoreOrderLine_fulfillmentChannel_idx"
    ON "product"."StoreOrderLine"("fulfillmentChannel");

CREATE TABLE "product"."StoreReturnLine" (
    "id" TEXT NOT NULL,
    "channel" "product"."StoreChannel" NOT NULL,
    "storeKey" TEXT NOT NULL,
    "idempotencyKey" TEXT NOT NULL,
    "amazonOrderId" TEXT,
    "sku" TEXT NOT NULL,
    "asin" TEXT,
    "productName" TEXT,
    "quantity" INTEGER NOT NULL DEFAULT 0,
    "returnDate" DATE NOT NULL,
    "reason" TEXT,
    "status" TEXT,
    "amazonFulfillment" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "StoreReturnLine_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "StoreReturnLine_idempotencyKey_key"
    ON "product"."StoreReturnLine"("idempotencyKey");
CREATE INDEX "StoreReturnLine_sku_returnDate_idx"
    ON "product"."StoreReturnLine"("sku", "returnDate");
CREATE INDEX "StoreReturnLine_storeKey_returnDate_idx"
    ON "product"."StoreReturnLine"("storeKey", "returnDate");

CREATE TABLE "product"."StoreReportJob" (
    "id" TEXT NOT NULL,
    "channel" "product"."StoreChannel" NOT NULL,
    "reportType" TEXT NOT NULL,
    "storeKey" TEXT NOT NULL,
    "dataStart" TIMESTAMPTZ(6) NOT NULL,
    "dataEnd" TIMESTAMPTZ(6) NOT NULL,
    "externalReportId" TEXT,
    "documentId" TEXT,
    "status" "product"."StoreReportStatus" NOT NULL DEFAULT 'REQUESTED',
    "importedAt" TIMESTAMPTZ(6),
    "errorMessage" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "StoreReportJob_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "StoreReportJob_window_key"
    ON "product"."StoreReportJob"("channel", "reportType", "storeKey", "dataStart", "dataEnd");
CREATE INDEX "StoreReportJob_status_createdAt_idx"
    ON "product"."StoreReportJob"("status", "createdAt");
