-- ============================================================================
-- Spedizioni FBA per riga ordine (28/10/2026).
--
-- Ordini mostrava «UE (rete FBA)» come partenza degli ordini FBA di marketplace
-- senza magazzino nostro (es. Amazon.se). Il report Amazon Fulfilled Shipments
-- dice per ogni riga spedita il centro logistico (BLQ1, LYS2, BCN4…), quindi il
-- paese reale di partenza, anche quando Amazon spedisce da un paese dove lo
-- stock non era previsto.
-- ============================================================================

CREATE TABLE "product"."StoreFbaShipmentItem" (
    "shipmentItemId" TEXT NOT NULL,
    "shipmentId" TEXT NOT NULL,
    "amazonOrderId" TEXT NOT NULL,
    "orderItemId" TEXT NOT NULL,
    "sku" TEXT NOT NULL DEFAULT '',
    "quantity" INTEGER NOT NULL DEFAULT 0,
    "shipmentDate" TIMESTAMPTZ(6) NOT NULL,
    "fulfillmentCenterId" TEXT NOT NULL,
    "salesChannel" TEXT NOT NULL DEFAULT '',
    "shipCountry" TEXT NOT NULL DEFAULT '',
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "StoreFbaShipmentItem_pkey" PRIMARY KEY ("shipmentItemId")
);

CREATE INDEX "StoreFbaShipmentItem_orderItemId_idx" ON "product"."StoreFbaShipmentItem"("orderItemId");
CREATE INDEX "StoreFbaShipmentItem_amazonOrderId_idx" ON "product"."StoreFbaShipmentItem"("amazonOrderId");
CREATE INDEX "StoreFbaShipmentItem_shipmentDate_idx" ON "product"."StoreFbaShipmentItem"("shipmentDate");
