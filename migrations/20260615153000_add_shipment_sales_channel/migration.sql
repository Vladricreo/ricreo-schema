CREATE TYPE inventory."ShipmentSalesChannel" AS ENUM (
  'AMAZON',
  'TEMU',
  'EBAY',
  'ETSY'
);

ALTER TABLE inventory."Shipment"
  ADD COLUMN "salesChannel" inventory."ShipmentSalesChannel";

CREATE INDEX "Shipment_salesChannel_idx"
  ON inventory."Shipment"("salesChannel");
