-- Aggiunge `shipmentConfirmationId` (es. `FBA15LQ4CBB1`) per le chiamate
-- SP-API Fulfillment Inbound v0 legacy: la v0 NON riconosce gli `sh...`
-- ID dell'API v2024-03-20 (rifiuta con `InvalidInput "Shipment not found
-- with merchant ... shipmentId = [sh...]"`). Va passato il vecchio
-- "ShipmentId" v0, equivalente al `shipmentConfirmationId` v2024.

ALTER TABLE inventory."FbaShipment"
  ADD COLUMN IF NOT EXISTS "shipmentConfirmationId" TEXT;

CREATE INDEX IF NOT EXISTS "FbaShipment_shipmentConfirmationId_idx"
  ON inventory."FbaShipment"("shipmentConfirmationId");

-- Backfill best-effort: il refresh etichette già salvava il confirmation
-- id dentro `amazonPayload` (chiave omonima). Lo promuoviamo in colonna
-- per gli shipment esistenti così non ricapita di dover rifare un refresh
-- prima del prossimo sync ricevuto.
UPDATE inventory."FbaShipment"
   SET "shipmentConfirmationId" = "amazonPayload"->>'shipmentConfirmationId'
 WHERE "shipmentConfirmationId" IS NULL
   AND "amazonPayload" IS NOT NULL
   AND "amazonPayload" ? 'shipmentConfirmationId'
   AND ("amazonPayload"->>'shipmentConfirmationId') IS NOT NULL
   AND length("amazonPayload"->>'shipmentConfirmationId') > 0;
