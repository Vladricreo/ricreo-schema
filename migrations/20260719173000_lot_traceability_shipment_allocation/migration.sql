-- Tracciabilità ISO 9001: allocazione lotto/spedizione (FIFO multi-lotto) + indice ProductionJob -> ProductionLot

-- CreateTable
CREATE TABLE "inventory"."ShipmentLotAllocation" (
    "id" UUID NOT NULL,
    "shipmentLineId" UUID NOT NULL,
    "lotId" UUID NOT NULL,
    "quantity" INTEGER NOT NULL,
    "movementId" UUID,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ShipmentLotAllocation_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "ShipmentLotAllocation_shipmentLineId_idx" ON "inventory"."ShipmentLotAllocation"("shipmentLineId");

-- CreateIndex
CREATE INDEX "ShipmentLotAllocation_lotId_idx" ON "inventory"."ShipmentLotAllocation"("lotId");

-- CreateIndex
CREATE INDEX "ShipmentLotAllocation_movementId_idx" ON "inventory"."ShipmentLotAllocation"("movementId");

-- CreateIndex (tracciabilità: risalire dai job di stampa al lotto di produzione)
CREATE INDEX "ProductionJob_productionLotId_idx" ON "print-farm"."ProductionJob"("productionLotId");

-- AddForeignKey
ALTER TABLE "inventory"."ShipmentLotAllocation" ADD CONSTRAINT "ShipmentLotAllocation_shipmentLineId_fkey" FOREIGN KEY ("shipmentLineId") REFERENCES "inventory"."ShipmentLine"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."ShipmentLotAllocation" ADD CONSTRAINT "ShipmentLotAllocation_lotId_fkey" FOREIGN KEY ("lotId") REFERENCES "inventory"."InventoryLot"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."ShipmentLotAllocation" ADD CONSTRAINT "ShipmentLotAllocation_movementId_fkey" FOREIGN KEY ("movementId") REFERENCES "inventory"."Movement"("id") ON DELETE SET NULL ON UPDATE CASCADE;
