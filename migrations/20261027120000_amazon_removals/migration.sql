-- Rimozioni Amazon (tab «Rimozioni Amazon» della pagina Resi di Inventory, 27/10/2026).
-- Solo aggiunte: tabelle nuove, due colonne nullable, indici. Nessun dato esistente cambia.

-- Enum
CREATE TYPE "inventory"."AmazonRemovalOrderType" AS ENUM ('RETURN', 'DISPOSAL', 'LIQUIDATION', 'OTHER');
CREATE TYPE "inventory"."AmazonRemovalStatus" AS ENUM ('IN_TRANSIT', 'PARTIALLY_RECEIVED', 'RECEIVED', 'CANCELLED');
CREATE TYPE "inventory"."OdetteSkuWithdrawalReason" AS ENUM ('FBA_SHIPMENT', 'FBM_SALE', 'SHELF', 'SCRAP', 'CORRECTION');

-- Ordini di rimozione importati dal report Amazon
CREATE TABLE "inventory"."AmazonRemovalOrder" (
    "id" UUID NOT NULL,
    "amazonOrderId" TEXT NOT NULL,
    "orderType" "inventory"."AmazonRemovalOrderType" NOT NULL DEFAULT 'RETURN',
    "amazonStatus" TEXT,
    "requestDate" TIMESTAMPTZ(6),
    "amazonUpdatedAt" TIMESTAMPTZ(6),
    "trackingNumbers" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "carriers" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "shippedAt" TIMESTAMPTZ(6),
    "status" "inventory"."AmazonRemovalStatus" NOT NULL DEFAULT 'IN_TRANSIT',
    "receivedAt" TIMESTAMPTZ(6),
    "notes" TEXT,
    "importedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AmazonRemovalOrder_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "AmazonRemovalOrder_amazonOrderId_key" ON "inventory"."AmazonRemovalOrder"("amazonOrderId");
CREATE INDEX "AmazonRemovalOrder_status_idx" ON "inventory"."AmazonRemovalOrder"("status");
CREATE INDEX "AmazonRemovalOrder_requestDate_idx" ON "inventory"."AmazonRemovalOrder"("requestDate" DESC);

-- Righe (SKU + disposition)
CREATE TABLE "inventory"."AmazonRemovalLine" (
    "id" UUID NOT NULL,
    "orderId" UUID NOT NULL,
    "sellerSku" TEXT NOT NULL,
    "fnsku" TEXT,
    "disposition" TEXT NOT NULL DEFAULT '',
    "skuId" UUID,
    "requestedQty" INTEGER NOT NULL DEFAULT 0,
    "shippedQty" INTEGER NOT NULL DEFAULT 0,
    "cancelledQty" INTEGER NOT NULL DEFAULT 0,
    "disposedQty" INTEGER NOT NULL DEFAULT 0,
    "inProcessQty" INTEGER NOT NULL DEFAULT 0,
    "receivedQty" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AmazonRemovalLine_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "AmazonRemovalLine_orderId_sellerSku_disposition_key" ON "inventory"."AmazonRemovalLine"("orderId", "sellerSku", "disposition");
CREATE INDEX "AmazonRemovalLine_skuId_idx" ON "inventory"."AmazonRemovalLine"("skuId");

ALTER TABLE "inventory"."AmazonRemovalLine" ADD CONSTRAINT "AmazonRemovalLine_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "inventory"."AmazonRemovalOrder"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "inventory"."AmazonRemovalLine" ADD CONSTRAINT "AmazonRemovalLine_skuId_fkey" FOREIGN KEY ("skuId") REFERENCES "inventory"."Sku"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- Storico prelievi dalle odette OMA
CREATE TABLE "inventory"."OdetteSkuWithdrawal" (
    "id" UUID NOT NULL,
    "odetteId" UUID NOT NULL,
    "skuId" UUID NOT NULL,
    "quantity" INTEGER NOT NULL,
    "reason" "inventory"."OdetteSkuWithdrawalReason" NOT NULL,
    "note" TEXT,
    "toLocationId" UUID,
    "movementId" UUID,
    "byUserId" INTEGER,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "OdetteSkuWithdrawal_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "OdetteSkuWithdrawal_odetteId_idx" ON "inventory"."OdetteSkuWithdrawal"("odetteId");
CREATE INDEX "OdetteSkuWithdrawal_skuId_idx" ON "inventory"."OdetteSkuWithdrawal"("skuId");
CREATE INDEX "OdetteSkuWithdrawal_createdAt_idx" ON "inventory"."OdetteSkuWithdrawal"("createdAt" DESC);

ALTER TABLE "inventory"."OdetteSkuWithdrawal" ADD CONSTRAINT "OdetteSkuWithdrawal_odetteId_fkey" FOREIGN KEY ("odetteId") REFERENCES "inventory"."Odette"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "inventory"."OdetteSkuWithdrawal" ADD CONSTRAINT "OdetteSkuWithdrawal_skuId_fkey" FOREIGN KEY ("skuId") REFERENCES "inventory"."Sku"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "inventory"."OdetteSkuWithdrawal" ADD CONSTRAINT "OdetteSkuWithdrawal_toLocationId_fkey" FOREIGN KEY ("toLocationId") REFERENCES "inventory"."WarehouseLocation"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "inventory"."OdetteSkuWithdrawal" ADD CONSTRAINT "OdetteSkuWithdrawal_movementId_fkey" FOREIGN KEY ("movementId") REFERENCES "inventory"."Movement"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "inventory"."OdetteSkuWithdrawal" ADD CONSTRAINT "OdetteSkuWithdrawal_byUserId_fkey" FOREIGN KEY ("byUserId") REFERENCES "public"."User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- Movimenti: collegamento alla riga di rimozione
ALTER TABLE "inventory"."Movement" ADD COLUMN "amazonRemovalLineId" UUID;
CREATE INDEX "Movement_amazonRemovalLineId_idx" ON "inventory"."Movement"("amazonRemovalLineId");
ALTER TABLE "inventory"."Movement" ADD CONSTRAINT "Movement_amazonRemovalLineId_fkey" FOREIGN KEY ("amazonRemovalLineId") REFERENCES "inventory"."AmazonRemovalLine"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- Contenuto odette: ultima verifica (NULL sulle righe SKU = da verificare)
ALTER TABLE "inventory"."OdetteContent" ADD COLUMN "checkedAt" TIMESTAMPTZ(6);

-- Le tabelle nuove di inventory nascono senza RLS: come le altre, solo Prisma (postgres) le legge.
ALTER TABLE "inventory"."AmazonRemovalOrder" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "inventory"."AmazonRemovalLine" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "inventory"."OdetteSkuWithdrawal" ENABLE ROW LEVEL SECURITY;
