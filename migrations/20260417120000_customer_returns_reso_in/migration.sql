-- Resi cliente: enum, tabelle, Movement.returnLineId, MovementType.RESO_IN

-- Valore enum movimento (commit separato consigliato in PG vecchi; qui IF NOT EXISTS richiede PG15+)
ALTER TYPE inventory."MovementType" ADD VALUE IF NOT EXISTS 'RESO_IN';

CREATE TYPE inventory."CustomerReturnOrigin" AS ENUM (
  'DELIVERY_FAILURE',
  'CUSTOMER_RETURN',
  'MANUAL'
);

CREATE TYPE inventory."CustomerReturnStatus" AS ENUM (
  'PENDING_INBOUND',
  'RECEIVED',
  'IN_INSPECTION',
  'COMPLETED',
  'SCRAPPED',
  'CANCELLED'
);

CREATE TYPE inventory."CustomerReturnLineCondition" AS ENUM (
  'TO_INSPECT',
  'REUSABLE',
  'RECOVERABLE_PARTS',
  'SCRAP'
);

CREATE TABLE inventory."CustomerReturn" (
    "id" UUID NOT NULL,
    "number" BIGSERIAL NOT NULL,
    "origin" inventory."CustomerReturnOrigin" NOT NULL,
    "status" inventory."CustomerReturnStatus" NOT NULL DEFAULT 'PENDING_INBOUND',
    "shipmentId" UUID,
    "orderNumberSnapshot" TEXT,
    "trackingNumberSnapshot" TEXT,
    "clientNameSnapshot" TEXT,
    "countrySnapshot" TEXT,
    "labelUrl" TEXT,
    "receivedAt" TIMESTAMPTZ(6),
    "completedAt" TIMESTAMPTZ(6),
    "notes" TEXT,
    "createdByUserId" INTEGER,
    "shippyProReturnId" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CustomerReturn_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "CustomerReturn_number_key" ON inventory."CustomerReturn"("number");

CREATE UNIQUE INDEX "CustomerReturn_shippyProReturnId_key" ON inventory."CustomerReturn"("shippyProReturnId");

CREATE INDEX "CustomerReturn_shipmentId_idx" ON inventory."CustomerReturn"("shipmentId");

CREATE INDEX "CustomerReturn_status_idx" ON inventory."CustomerReturn"("status");

CREATE INDEX "CustomerReturn_createdAt_idx" ON inventory."CustomerReturn"("createdAt" DESC);

ALTER TABLE inventory."CustomerReturn" ADD CONSTRAINT "CustomerReturn_shipmentId_fkey" FOREIGN KEY ("shipmentId") REFERENCES inventory."Shipment"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE inventory."CustomerReturn" ADD CONSTRAINT "CustomerReturn_createdByUserId_fkey" FOREIGN KEY ("createdByUserId") REFERENCES public."User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

CREATE TABLE inventory."CustomerReturnLine" (
    "id" UUID NOT NULL,
    "customerReturnId" UUID NOT NULL,
    "skuId" UUID,
    "productId" UUID,
    "shipmentLineId" UUID,
    "quantity" INTEGER NOT NULL DEFAULT 1,
    "lineCondition" inventory."CustomerReturnLineCondition" NOT NULL DEFAULT 'TO_INSPECT',
    "notes" TEXT,
    "inventoryReceivedAt" TIMESTAMPTZ(6),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CustomerReturnLine_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "CustomerReturnLine_customerReturnId_idx" ON inventory."CustomerReturnLine"("customerReturnId");

CREATE INDEX "CustomerReturnLine_skuId_idx" ON inventory."CustomerReturnLine"("skuId");

CREATE INDEX "CustomerReturnLine_productId_idx" ON inventory."CustomerReturnLine"("productId");

ALTER TABLE inventory."CustomerReturnLine" ADD CONSTRAINT "CustomerReturnLine_customerReturnId_fkey" FOREIGN KEY ("customerReturnId") REFERENCES inventory."CustomerReturn"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE inventory."CustomerReturnLine" ADD CONSTRAINT "CustomerReturnLine_skuId_fkey" FOREIGN KEY ("skuId") REFERENCES inventory."Sku"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE inventory."CustomerReturnLine" ADD CONSTRAINT "CustomerReturnLine_productId_fkey" FOREIGN KEY ("productId") REFERENCES inventory."Product"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE inventory."CustomerReturnLine" ADD CONSTRAINT "CustomerReturnLine_shipmentLineId_fkey" FOREIGN KEY ("shipmentLineId") REFERENCES inventory."ShipmentLine"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE inventory."Movement" ADD COLUMN "returnLineId" UUID;

CREATE INDEX "Movement_returnLineId_idx" ON inventory."Movement"("returnLineId");

ALTER TABLE inventory."Movement" ADD CONSTRAINT "Movement_returnLineId_fkey" FOREIGN KEY ("returnLineId") REFERENCES inventory."CustomerReturnLine"("id") ON DELETE SET NULL ON UPDATE CASCADE;
