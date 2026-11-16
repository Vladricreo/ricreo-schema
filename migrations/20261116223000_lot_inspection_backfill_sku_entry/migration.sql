-- Controllo qualità dei lotti (R-243, 16/11/2026) — storico 3.
-- I lotti di prodotto finito ancora senza controllo dopo la migrazione precedente
-- (le sessioni di assemblaggio spesso puntano al lotto di fase, non a quello finale)
-- si coprono con l'ingresso a magazzino del prodotto finito: il movimento PRODUZIONE
-- registrato dall'operatore che ha chiuso i pezzi sull'ordine di assemblaggio.
-- Solo movimenti con operatore. Idempotente (NOT EXISTS sulla stessa registrazione).

INSERT INTO "inventory"."LotInspection" (
  "id", "lotId", "inspectedAt", "inspectedBy", "result", "notes", "source",
  "quantityChecked", "assemblyOrderId", "createdAt", "updatedAt"
)
SELECT gen_random_uuid(),
       m."lotId",
       m.date,
       m."byUserId",
       'PASSED'::"inventory"."LotInspectionResult",
       format(
         'Ricostruito il 16/11/2026 dall''ingresso a magazzino del prodotto finito%s: %s pezzi accettati dall''operatore.',
         CASE WHEN ao.number IS NOT NULL THEN ' (ordine AA-' || ao.number || ')' ELSE '' END,
         m.quantity
       ),
       'ASSEMBLY_BACKFILL'::"inventory"."LotInspectionSource",
       m.quantity,
       m."assemblyOrderId",
       now(),
       now()
FROM "inventory"."Movement" m
JOIN "inventory"."InventoryLot" l ON l.id = m."lotId"
LEFT JOIN "inventory"."AssemblyOrder" ao ON ao.id = m."assemblyOrderId"
WHERE m.type = 'PRODUZIONE'
  AND m."byUserId" IS NOT NULL
  AND m.quantity > 0
  AND l."productId" IS NOT NULL
  AND l."productPartId" IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM "inventory"."LotInspection" i WHERE i."lotId" = l.id
  );
