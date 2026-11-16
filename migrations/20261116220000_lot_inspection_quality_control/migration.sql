-- Controllo qualità dei lotti (R-243, 16/11/2026).
-- 1) LotInspection sa da dove nasce il controllo (manuale, chiusura assemblaggio,
--    ricostruito da scarico o da sessione di assemblaggio), quanti pezzi copre e a
--    quale ordine/sessione/scarico si riferisce.
-- 2) Storico: ricostruisce i controlli dalle registrazioni originali che hanno
--    già operatore e ora (pezzi accettati allo scarico, pezzi buoni/scarti di una
--    sessione di assemblaggio chiusa). `inspectedAt`/`inspectedBy` sono quelli
--    dell'evento originale; `createdAt` resta la data di questa migrazione, così
--    si distingue sempre un controllo ricostruito da uno registrato sul momento.
--    Idempotente (ON CONFLICT DO NOTHING sulle chiavi univoche).

-- CreateEnum
CREATE TYPE "inventory"."LotInspectionSource" AS ENUM ('MANUAL', 'ASSEMBLY_CLOSE', 'HARVEST_BACKFILL', 'ASSEMBLY_BACKFILL');

-- AlterTable
ALTER TABLE "inventory"."LotInspection" ADD COLUMN     "assemblyOperationId" UUID,
ADD COLUMN     "assemblyOrderId" UUID,
ADD COLUMN     "harvestId" UUID,
ADD COLUMN     "quantityChecked" INTEGER,
ADD COLUMN     "quantityRejected" INTEGER,
ADD COLUMN     "source" "inventory"."LotInspectionSource" NOT NULL DEFAULT 'MANUAL';

-- CreateIndex
CREATE INDEX "LotInspection_assemblyOrderId_idx" ON "inventory"."LotInspection"("assemblyOrderId");

-- CreateIndex
CREATE UNIQUE INDEX "LotInspection_harvestId_lotId_key" ON "inventory"."LotInspection"("harvestId", "lotId");

-- CreateIndex
CREATE UNIQUE INDEX "LotInspection_assemblyOperationId_lotId_key" ON "inventory"."LotInspection"("assemblyOperationId", "lotId");

-- AddForeignKey
ALTER TABLE "inventory"."LotInspection" ADD CONSTRAINT "LotInspection_assemblyOrderId_fkey" FOREIGN KEY ("assemblyOrderId") REFERENCES "inventory"."AssemblyOrder"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."LotInspection" ADD CONSTRAINT "LotInspection_assemblyOperationId_fkey" FOREIGN KEY ("assemblyOperationId") REFERENCES "inventory"."AssemblyOperation"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."LotInspection" ADD CONSTRAINT "LotInspection_harvestId_fkey" FOREIGN KEY ("harvestId") REFERENCES "print-farm"."PrinterHarvest"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Storico 1: pezzi accettati allo scarico, una riga per (scarico, lotto).
-- Gli scarti si attribuiscono al lotto solo quando lo scarico ha alimentato un solo lotto.
WITH per_lot AS (
  SELECT m."harvestId" AS harvest_id,
         m."lotId" AS lot_id,
         SUM(m.quantity)::int AS qty,
         COUNT(*) OVER (PARTITION BY m."harvestId") AS n_lots
  FROM "inventory"."Movement" m
  WHERE m.type = 'PRODUZIONE'
    AND m."harvestId" IS NOT NULL
    AND m."lotId" IS NOT NULL
  GROUP BY m."harvestId", m."lotId"
)
INSERT INTO "inventory"."LotInspection" (
  "id", "lotId", "inspectedAt", "inspectedBy", "result", "notes", "source",
  "quantityChecked", "quantityRejected", "harvestId", "createdAt", "updatedAt"
)
SELECT gen_random_uuid(),
       pl.lot_id,
       h."harvestedAt",
       h."harvestedByUserId",
       'PASSED'::"inventory"."LotInspectionResult",
       format(
         'Ricostruito il 16/11/2026 dallo scarico di %s: %s pezzi accettati in questo lotto (scarico: %s accettati, %s scartati). Operatore = account collegato al tablet.',
         regexp_replace(p.name, '\s+', ' ', 'g'), pl.qty, h."partsAccepted", h."partsRejected"
       ),
       'HARVEST_BACKFILL'::"inventory"."LotInspectionSource",
       pl.qty + CASE WHEN pl.n_lots = 1 THEN h."partsRejected" ELSE 0 END,
       CASE WHEN pl.n_lots = 1 THEN h."partsRejected" ELSE NULL END,
       h.id,
       now(),
       now()
FROM per_lot pl
JOIN "print-farm"."PrinterHarvest" h ON h.id = pl.harvest_id
JOIN "print-farm"."Printer" p ON p.id = h."printerId"
WHERE pl.qty > 0
ON CONFLICT ("harvestId", "lotId") DO NOTHING;

-- Storico 2: sessioni di assemblaggio chiuse con pezzi buoni sul lotto.
INSERT INTO "inventory"."LotInspection" (
  "id", "lotId", "inspectedAt", "inspectedBy", "result", "notes", "source",
  "quantityChecked", "quantityRejected", "assemblyOrderId", "assemblyOperationId",
  "createdAt", "updatedAt"
)
SELECT gen_random_uuid(),
       o."lotId",
       COALESCE(o."endedAt", o."lastActivityAt", o."startedAt"),
       o."operatorId",
       'PASSED'::"inventory"."LotInspectionResult",
       format(
         'Ricostruito il 16/11/2026 dalla sessione di assemblaggio AA-%s (%s): %s pezzi buoni, %s scartati.',
         ao.number, o.type, o."quantityProduced", o."quantityScrapped"
       ),
       'ASSEMBLY_BACKFILL'::"inventory"."LotInspectionSource",
       o."quantityProduced" + o."quantityScrapped",
       o."quantityScrapped",
       o."assemblyOrderId",
       o.id,
       now(),
       now()
FROM "inventory"."AssemblyOperation" o
JOIN "inventory"."AssemblyOrder" ao ON ao.id = o."assemblyOrderId"
WHERE o."lotId" IS NOT NULL
  AND o."quantityProduced" > 0
  AND o."endedAt" IS NOT NULL
ON CONFLICT ("assemblyOperationId", "lotId") DO NOTHING;
