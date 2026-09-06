-- Reclamo unità FBA non ricevute: snapshot ricevute, ignore, case e messaggi.
-- Solo schema product.

CREATE TYPE "product"."FbaMissingUnitClaimStatus" AS ENUM ('IN_PROGRESS', 'WAITING', 'REFUNDED');

CREATE TABLE IF NOT EXISTS "product"."FbaInboundReceiptItem" (
    "id" TEXT NOT NULL,
    "shipmentId" UUID NOT NULL,
    "amazonShipmentId" TEXT,
    "shipmentConfirmationId" TEXT NOT NULL,
    "marketplaceId" TEXT NOT NULL,
    "sku" TEXT NOT NULL,
    "fnsku" TEXT,
    "asin" TEXT,
    "title" TEXT NOT NULL DEFAULT '',
    "quantityShipped" INTEGER NOT NULL DEFAULT 0,
    "quantityReceived" INTEGER NOT NULL DEFAULT 0,
    "shippedAt" TIMESTAMPTZ(6),
    "syncedAt" TIMESTAMPTZ(6) NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "FbaInboundReceiptItem_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "FbaInboundReceiptItem_ship_sku"
    ON "product"."FbaInboundReceiptItem" ("shipmentConfirmationId", "sku");
CREATE INDEX IF NOT EXISTS "FbaInboundReceiptItem_sku"
    ON "product"."FbaInboundReceiptItem" ("sku");
CREATE INDEX IF NOT EXISTS "FbaInboundReceiptItem_asin"
    ON "product"."FbaInboundReceiptItem" ("asin");
CREATE INDEX IF NOT EXISTS "FbaInboundReceiptItem_shipment"
    ON "product"."FbaInboundReceiptItem" ("shipmentId");

CREATE TABLE IF NOT EXISTS "product"."FbaInboundReceiptSyncJob" (
    "id" TEXT NOT NULL,
    "cursor" INTEGER NOT NULL DEFAULT 0,
    "processed" INTEGER NOT NULL DEFAULT 0,
    "total" INTEGER NOT NULL DEFAULT 0,
    "status" "product"."StoreReportStatus" NOT NULL DEFAULT 'REQUESTED',
    "lastMessage" TEXT,
    "importedAt" TIMESTAMPTZ(6),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "FbaInboundReceiptSyncJob_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "product"."FbaMissingUnitIgnore" (
    "id" TEXT NOT NULL,
    "sku" TEXT NOT NULL,
    "reason" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "FbaMissingUnitIgnore_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "FbaMissingUnitIgnore_sku"
    ON "product"."FbaMissingUnitIgnore" ("sku");

CREATE TABLE IF NOT EXISTS "product"."FbaMissingUnitClaim" (
    "id" TEXT NOT NULL,
    "sku" TEXT NOT NULL,
    "asin" TEXT,
    "fnsku" TEXT,
    "sellerId" TEXT NOT NULL,
    "status" "product"."FbaMissingUnitClaimStatus" NOT NULL DEFAULT 'IN_PROGRESS',
    "shipmentId" UUID,
    "shipmentConfirmationId" TEXT NOT NULL,
    "amazonShipmentId" TEXT,
    "quantityShipped" INTEGER NOT NULL DEFAULT 0,
    "quantityReceived" INTEGER NOT NULL DEFAULT 0,
    "quantityMissing" INTEGER NOT NULL DEFAULT 0,
    "caseId" TEXT,
    "caseOpenedAt" TIMESTAMPTZ(6),
    "refundedQuantity" INTEGER,
    "refundedAt" TIMESTAMPTZ(6),
    "excelGeneratedAt" TIMESTAMPTZ(6),
    "lastMessageSyncAt" TIMESTAMPTZ(6),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "FbaMissingUnitClaim_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "FbaMissingUnitClaim_sku_ship"
    ON "product"."FbaMissingUnitClaim" ("sku", "shipmentConfirmationId");
CREATE INDEX IF NOT EXISTS "FbaMissingUnitClaim_sku"
    ON "product"."FbaMissingUnitClaim" ("sku");
CREATE INDEX IF NOT EXISTS "FbaMissingUnitClaim_status"
    ON "product"."FbaMissingUnitClaim" ("status");
CREATE INDEX IF NOT EXISTS "FbaMissingUnitClaim_case"
    ON "product"."FbaMissingUnitClaim" ("caseId");

CREATE TABLE IF NOT EXISTS "product"."FbaMissingUnitClaimMessage" (
    "id" TEXT NOT NULL,
    "claimId" TEXT NOT NULL,
    "caseId" TEXT,
    "source" TEXT NOT NULL,
    "direction" TEXT NOT NULL DEFAULT 'system',
    "title" TEXT,
    "body" TEXT NOT NULL,
    "occurredAt" TIMESTAMPTZ(6) NOT NULL,
    "raw" JSONB,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "FbaMissingUnitClaimMessage_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "FbaMissingUnitClaimMessage_claim"
    ON "product"."FbaMissingUnitClaimMessage" ("claimId", "occurredAt");

ALTER TABLE "product"."FbaMissingUnitClaimMessage"
    ADD CONSTRAINT "FbaMissingUnitClaimMessage_claim_fkey"
    FOREIGN KEY ("claimId") REFERENCES "product"."FbaMissingUnitClaim"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
