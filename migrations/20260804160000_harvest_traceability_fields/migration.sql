-- Tracciabilità scarichi (harvest): dati necessari per un annullamento esatto
-- e per distinguere gli scarichi "saltati" dagli scarti di qualità.

-- AlterTable
ALTER TABLE "print-farm"."PrinterHarvest"
ADD COLUMN "assignmentStatusAtHarvest" TEXT,
ADD COLUMN "wasSkipped" BOOLEAN NOT NULL DEFAULT false;

-- Backfill: gli scarichi storici senza pezzi raccolti erano di fatto dei "salta scarico".
UPDATE "print-farm"."PrinterHarvest"
SET "wasSkipped" = true
WHERE "partsTotal" = 0
  AND "partsAccepted" = 0
  AND "partsRejected" = 0;

-- AlterTable
ALTER TABLE "inventory"."Movement"
ADD COLUMN "harvestId" UUID;

-- CreateIndex
CREATE INDEX "Movement_harvestId_idx"
ON "inventory"."Movement"("harvestId");

-- AddForeignKey
ALTER TABLE "inventory"."Movement"
ADD CONSTRAINT "Movement_harvestId_fkey"
FOREIGN KEY ("harvestId")
REFERENCES "print-farm"."PrinterHarvest"("id")
ON DELETE SET NULL
ON UPDATE CASCADE;
