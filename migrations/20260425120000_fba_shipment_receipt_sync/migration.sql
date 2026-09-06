-- Stati shipment Amazon (v0) + colonne sync ricevuto + tabella righe MSKU.

ALTER TYPE "inventory"."FbaShipmentStatus" ADD VALUE IF NOT EXISTS 'IN_TRANSIT';
ALTER TYPE "inventory"."FbaShipmentStatus" ADD VALUE IF NOT EXISTS 'DELIVERED';
ALTER TYPE "inventory"."FbaShipmentStatus" ADD VALUE IF NOT EXISTS 'CHECKED_IN';
ALTER TYPE "inventory"."FbaShipmentStatus" ADD VALUE IF NOT EXISTS 'RECEIVING';
ALTER TYPE "inventory"."FbaShipmentStatus" ADD VALUE IF NOT EXISTS 'CLOSED';

ALTER TABLE inventory."FbaShipment"
  ADD COLUMN IF NOT EXISTS "lastReceiptSyncAt" TIMESTAMPTZ(6),
  ADD COLUMN IF NOT EXISTS "totalShipped" INTEGER,
  ADD COLUMN IF NOT EXISTS "totalReceived" INTEGER;

CREATE TABLE IF NOT EXISTS inventory."FbaShipmentReceiptItem" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "shipmentId" UUID NOT NULL,
  "msku" TEXT NOT NULL,
  "fnsku" TEXT,
  "quantityShipped" INTEGER NOT NULL DEFAULT 0,
  "quantityReceived" INTEGER NOT NULL DEFAULT 0,
  "syncedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "FbaShipmentReceiptItem_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "FbaShipmentReceiptItem_shipmentId_msku_key"
  ON inventory."FbaShipmentReceiptItem"("shipmentId", "msku");
CREATE INDEX IF NOT EXISTS "FbaShipmentReceiptItem_shipmentId_idx"
  ON inventory."FbaShipmentReceiptItem"("shipmentId");

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'FbaShipmentReceiptItem_shipmentId_fkey'
  ) THEN
    ALTER TABLE inventory."FbaShipmentReceiptItem"
      ADD CONSTRAINT "FbaShipmentReceiptItem_shipmentId_fkey"
      FOREIGN KEY ("shipmentId") REFERENCES inventory."FbaShipment"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;
