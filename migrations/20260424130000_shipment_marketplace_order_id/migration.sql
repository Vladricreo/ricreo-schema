-- Aggiunge il numero d'ordine del marketplace originale (Amazon/Etsy/eBay/Shopify, ...)
-- a `Shipment`. Corrisponde a ShippyPro `transaction_id`, distinto da
-- `orderNumber` che è l'ID interno del provider (ShippyPro `ordine_id`).

ALTER TABLE inventory."Shipment"
  ADD COLUMN "marketplaceOrderId" TEXT;

CREATE INDEX "Shipment_marketplaceOrderId_idx"
  ON inventory."Shipment"("marketplaceOrderId");
