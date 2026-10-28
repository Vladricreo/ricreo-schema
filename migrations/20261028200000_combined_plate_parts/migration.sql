-- Piatti combinati, fasi 4-7 (28/10, R-122/R-124/R-126, audits/2026-10-28-piatti-combinati/PIANO.md):
-- righe parte dei piatti combinati e conteggi per parte di scarico, bozza e task Gantt. Solo aggiunte.
-- AlterTable
ALTER TABLE "print-farm"."PrinterHarvest" ADD COLUMN     "partsBreakdown" JSONB;

-- AlterTable
ALTER TABLE "print-farm"."GanttTask" ADD COLUMN     "partsBreakdown" JSONB;

-- AlterTable
ALTER TABLE "print-farm"."HarvestDraft" ADD COLUMN     "partsBreakdown" JSONB;

-- CreateTable
CREATE TABLE "print-farm"."PrinterAssignmentPart" (
    "id" UUID NOT NULL,
    "assignmentId" UUID NOT NULL,
    "productionJobId" UUID NOT NULL,
    "productPartId" UUID,
    "partsExpected" INTEGER NOT NULL,
    "partsProduced" INTEGER NOT NULL DEFAULT 0,
    "partsRejected" INTEGER NOT NULL DEFAULT 0,
    "objectIds" INTEGER[] DEFAULT ARRAY[]::INTEGER[],
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PrinterAssignmentPart_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "PrinterAssignmentPart_productionJobId_idx" ON "print-farm"."PrinterAssignmentPart"("productionJobId");

-- CreateIndex
CREATE INDEX "PrinterAssignmentPart_productPartId_idx" ON "print-farm"."PrinterAssignmentPart"("productPartId");

-- CreateIndex
CREATE UNIQUE INDEX "PrinterAssignmentPart_assignmentId_productionJobId_key" ON "print-farm"."PrinterAssignmentPart"("assignmentId", "productionJobId");

-- AddForeignKey
ALTER TABLE "print-farm"."PrinterAssignmentPart" ADD CONSTRAINT "PrinterAssignmentPart_assignmentId_fkey" FOREIGN KEY ("assignmentId") REFERENCES "print-farm"."PrinterAssignment"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."PrinterAssignmentPart" ADD CONSTRAINT "PrinterAssignmentPart_productionJobId_fkey" FOREIGN KEY ("productionJobId") REFERENCES "print-farm"."ProductionJob"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."PrinterAssignmentPart" ADD CONSTRAINT "PrinterAssignmentPart_productPartId_fkey" FOREIGN KEY ("productPartId") REFERENCES "inventory"."ProductPart"("id") ON DELETE SET NULL ON UPDATE CASCADE;

