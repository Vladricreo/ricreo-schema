-- Rimborso packaging secondario: FK sul movimento e testata/righe per spedizione.

ALTER TABLE "inventory"."Movement"
ADD COLUMN "packagingRefundShipmentId" UUID;

CREATE INDEX "Movement_packagingRefundShipmentId_idx"
ON "inventory"."Movement"("packagingRefundShipmentId");

ALTER TABLE "inventory"."Movement"
ADD CONSTRAINT "Movement_packagingRefundShipmentId_fkey"
FOREIGN KEY ("packagingRefundShipmentId") REFERENCES "inventory"."Shipment"("id")
ON DELETE SET NULL ON UPDATE CASCADE;

CREATE TABLE "inventory"."ShipmentPackagingRefund" (
    "id" UUID NOT NULL,
    "shipmentId" UUID NOT NULL,
    "createdByUserId" INTEGER,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ShipmentPackagingRefund_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "ShipmentPackagingRefund_shipmentId_key"
ON "inventory"."ShipmentPackagingRefund"("shipmentId");

CREATE INDEX "ShipmentPackagingRefund_createdByUserId_idx"
ON "inventory"."ShipmentPackagingRefund"("createdByUserId");

ALTER TABLE "inventory"."ShipmentPackagingRefund"
ADD CONSTRAINT "ShipmentPackagingRefund_shipmentId_fkey"
FOREIGN KEY ("shipmentId") REFERENCES "inventory"."Shipment"("id")
ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "inventory"."ShipmentPackagingRefund"
ADD CONSTRAINT "ShipmentPackagingRefund_createdByUserId_fkey"
FOREIGN KEY ("createdByUserId") REFERENCES "public"."User"("id")
ON DELETE SET NULL ON UPDATE CASCADE;

CREATE TABLE "inventory"."ShipmentPackagingRefundLine" (
    "id" UUID NOT NULL,
    "refundId" UUID NOT NULL,
    "shipmentLineId" UUID NOT NULL,
    "itemSpecId" UUID NOT NULL,
    "itemId" UUID NOT NULL,
    "quantity" INTEGER NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ShipmentPackagingRefundLine_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "ShipmentPackagingRefundLine_refundId_shipmentLineId_itemSpecId_key"
ON "inventory"."ShipmentPackagingRefundLine"("refundId", "shipmentLineId", "itemSpecId");

CREATE INDEX "ShipmentPackagingRefundLine_shipmentLineId_idx"
ON "inventory"."ShipmentPackagingRefundLine"("shipmentLineId");

CREATE INDEX "ShipmentPackagingRefundLine_itemSpecId_idx"
ON "inventory"."ShipmentPackagingRefundLine"("itemSpecId");

CREATE INDEX "ShipmentPackagingRefundLine_itemId_idx"
ON "inventory"."ShipmentPackagingRefundLine"("itemId");

ALTER TABLE "inventory"."ShipmentPackagingRefundLine"
ADD CONSTRAINT "ShipmentPackagingRefundLine_refundId_fkey"
FOREIGN KEY ("refundId") REFERENCES "inventory"."ShipmentPackagingRefund"("id")
ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "inventory"."ShipmentPackagingRefundLine"
ADD CONSTRAINT "ShipmentPackagingRefundLine_shipmentLineId_fkey"
FOREIGN KEY ("shipmentLineId") REFERENCES "inventory"."ShipmentLine"("id")
ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "inventory"."ShipmentPackagingRefundLine"
ADD CONSTRAINT "ShipmentPackagingRefundLine_itemSpecId_fkey"
FOREIGN KEY ("itemSpecId") REFERENCES "inventory"."ItemSpec"("id")
ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "inventory"."ShipmentPackagingRefundLine"
ADD CONSTRAINT "ShipmentPackagingRefundLine_itemId_fkey"
FOREIGN KEY ("itemId") REFERENCES "inventory"."Item"("id")
ON DELETE RESTRICT ON UPDATE CASCADE;
