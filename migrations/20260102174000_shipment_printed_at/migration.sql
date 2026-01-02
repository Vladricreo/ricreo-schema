-- Aggiunge `printedAt` per distinguere stampa interna vs provider.

ALTER TABLE "inventory"."Shipment"
ADD COLUMN "printedAt" TIMESTAMPTZ;
