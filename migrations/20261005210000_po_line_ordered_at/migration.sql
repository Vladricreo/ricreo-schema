-- Data d'ordine sulla singola riga: la ricezione sposta la riga su un ordine
-- RECEIVED (solo receivedAt) e cancella l'ordine ORDERED, perdendo la data.
-- Serve per il tempo di consegna reale per fornitore (pagina Fornitori).
ALTER TABLE "inventory"."PurchaseOrderLine"
  ADD COLUMN IF NOT EXISTS "orderedAt" TIMESTAMPTZ(6);

-- Backfill: righe ancora su ordini ORDERED ereditano la data dell'ordine.
-- Le ricezioni passate non hanno una data d'ordine recuperabile.
UPDATE "inventory"."PurchaseOrderLine" l
SET "orderedAt" = o."orderedAt"
FROM "inventory"."PurchaseOrder" o
WHERE o.id = l."orderId"
  AND o.status = 'ORDERED'
  AND o."orderedAt" IS NOT NULL
  AND l."orderedAt" IS NULL;
