-- Ordine di completamento (solo parti mancanti) e quale sia sullo stesso assemblaggio.
-- Più completamenti possono convivere: completionIndex è 1, poi 2, …
-- I NULL restano distinti in Postgres, quindi gli ordini normali non collidono.

ALTER TABLE "inventory"."ProductOrder"
  ADD COLUMN "isCompletionOrder" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN "completionIndex" INTEGER;

CREATE INDEX "ProductOrder_isCompletionOrder_idx"
  ON "inventory"."ProductOrder" ("isCompletionOrder");

-- Storico: i PO solo-parti collegati a un assemblaggio sono completamenti.
WITH ranked AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY "assemblyOrderId"
      ORDER BY "createdAt" ASC, "number" ASC
    ) AS idx
  FROM "inventory"."ProductOrder"
  WHERE "assemblyOrderId" IS NOT NULL
    AND "quantityToProduce" = 0
)
UPDATE "inventory"."ProductOrder" AS po
SET
  "isCompletionOrder" = true,
  "completionIndex" = ranked.idx,
  "lane" = COALESCE(po."lane", 'COMPLETAMENTO_KIT'::"inventory"."ProductOrderLane")
FROM ranked
WHERE po.id = ranked.id;

-- Scadenza: giorno di calendario successivo alla creazione (Europe/Rome), solo se manca.
UPDATE "inventory"."ProductOrder"
SET
  "dueDate" = (
    (date_trunc('day', "createdAt" AT TIME ZONE 'Europe/Rome') + INTERVAL '1 day')
    AT TIME ZONE 'Europe/Rome'
  ),
  "dueDateOrigin" = 'KIT'::"inventory"."ProductOrderDueDateOrigin"
WHERE "isCompletionOrder" = true
  AND "dueDate" IS NULL;

ALTER TABLE "inventory"."ProductOrder"
  ADD CONSTRAINT "ProductOrder_assemblyOrderId_completionIndex_key"
  UNIQUE ("assemblyOrderId", "completionIndex");
