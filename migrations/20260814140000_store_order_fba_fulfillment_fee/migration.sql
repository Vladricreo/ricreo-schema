-- Fee FBA reali (Finances API) e cursore di paginazione.
-- Solo schema product.

CREATE INDEX IF NOT EXISTS "StoreOrderLine_amazonOrderId_idx"
    ON "product"."StoreOrderLine"("amazonOrderId");

CREATE TABLE "product"."StoreOrderFee" (
    "id" TEXT NOT NULL,
    "channel" "product"."StoreChannel" NOT NULL,
    "amazonOrderId" TEXT NOT NULL,
    "orderItemId" TEXT NOT NULL DEFAULT '',
    "sku" TEXT NOT NULL,
    "fbaFulfillmentFee" DECIMAL(12,4) NOT NULL,
    "currency" TEXT NOT NULL DEFAULT 'EUR',
    "postedDate" TIMESTAMPTZ(6),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "StoreOrderFee_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "StoreOrderFee_item_key"
    ON "product"."StoreOrderFee"("channel", "amazonOrderId", "orderItemId", "sku");
CREATE INDEX "StoreOrderFee_sku_idx"
    ON "product"."StoreOrderFee"("sku");
CREATE INDEX "StoreOrderFee_order_idx"
    ON "product"."StoreOrderFee"("amazonOrderId");

CREATE TABLE "product"."StoreFinanceCursor" (
    "id" TEXT NOT NULL,
    "channel" "product"."StoreChannel" NOT NULL,
    "storeKey" TEXT NOT NULL,
    "dataStart" TIMESTAMPTZ(6) NOT NULL,
    "dataEnd" TIMESTAMPTZ(6) NOT NULL,
    "nextToken" TEXT,
    "status" "product"."StoreReportStatus" NOT NULL DEFAULT 'REQUESTED',
    "pagesFetched" INTEGER NOT NULL DEFAULT 0,
    "itemsUpserted" INTEGER NOT NULL DEFAULT 0,
    "importedAt" TIMESTAMPTZ(6),
    "errorMessage" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "StoreFinanceCursor_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "StoreFinanceCursor_window_key"
    ON "product"."StoreFinanceCursor"("channel", "storeKey", "dataStart", "dataEnd");
CREATE INDEX "StoreFinanceCursor_status_idx"
    ON "product"."StoreFinanceCursor"("status", "createdAt");
