-- Inbox CS persistita: richieste post-vendita + storico stati + job import.

CREATE TABLE "product"."AfterSalesRequest" (
    "id" TEXT NOT NULL,
    "externalKey" TEXT NOT NULL,
    "channel" "product"."StoreChannel" NOT NULL,
    "kind" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "statusLabel" TEXT NOT NULL DEFAULT '',
    "previousStatus" TEXT,
    "statusChangedAt" TIMESTAMPTZ(6),
    "orderId" TEXT NOT NULL DEFAULT '',
    "sku" TEXT NOT NULL DEFAULT '',
    "asin" TEXT,
    "listingId" TEXT,
    "title" TEXT NOT NULL DEFAULT '',
    "imageUrl" TEXT NOT NULL DEFAULT '',
    "quantity" INTEGER NOT NULL DEFAULT 0,
    "reason" TEXT,
    "reasonDescription" TEXT,
    "requestedAt" TIMESTAMPTZ(6) NOT NULL,
    "dueAt" TIMESTAMPTZ(6),
    "marketplaceUrl" TEXT,
    "fulfillment" TEXT,
    "shipCountry" TEXT,
    "shipCountryName" TEXT,
    "afterSalesSn" TEXT,
    "parentAfterSalesSn" TEXT,
    "firstSeenAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lastSeenAt" TIMESTAMPTZ(6) NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "AfterSalesRequest_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "AfterSalesRequest_externalKey_key" ON "product"."AfterSalesRequest"("externalKey");
CREATE INDEX "AfterSalesRequest_channel_status" ON "product"."AfterSalesRequest"("channel", "status", "requestedAt");
CREATE INDEX "AfterSalesRequest_channel_kind" ON "product"."AfterSalesRequest"("channel", "kind", "requestedAt");
CREATE INDEX "AfterSalesRequest_order" ON "product"."AfterSalesRequest"("orderId");
CREATE INDEX "AfterSalesRequest_after_sn" ON "product"."AfterSalesRequest"("afterSalesSn");

CREATE TABLE "product"."AfterSalesRequestStatusChange" (
    "id" TEXT NOT NULL,
    "requestId" TEXT NOT NULL,
    "fromStatus" TEXT NOT NULL,
    "toStatus" TEXT NOT NULL,
    "fromLabel" TEXT,
    "toLabel" TEXT,
    "changedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AfterSalesRequestStatusChange_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "AfterSalesRequestStatusChange_req" ON "product"."AfterSalesRequestStatusChange"("requestId", "changedAt");

ALTER TABLE "product"."AfterSalesRequestStatusChange"
ADD CONSTRAINT "AfterSalesRequestStatusChange_requestId_fkey"
FOREIGN KEY ("requestId") REFERENCES "product"."AfterSalesRequest"("id")
ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "product"."AfterSalesImportJob" (
    "id" TEXT NOT NULL,
    "capturedAt" DATE NOT NULL,
    "phase" TEXT NOT NULL DEFAULT 'amazon',
    "status" "product"."StoreReportStatus" NOT NULL DEFAULT 'REQUESTED',
    "lastMessage" TEXT,
    "errorMessage" TEXT,
    "channelErrors" JSONB,
    "upserted" INTEGER NOT NULL DEFAULT 0,
    "createdCount" INTEGER NOT NULL DEFAULT 0,
    "statusChanges" INTEGER NOT NULL DEFAULT 0,
    "importedAt" TIMESTAMPTZ(6),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "AfterSalesImportJob_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "AfterSalesImportJob_day_key" ON "product"."AfterSalesImportJob"("capturedAt");
CREATE INDEX "AfterSalesImportJob_status_idx" ON "product"."AfterSalesImportJob"("status", "capturedAt");
