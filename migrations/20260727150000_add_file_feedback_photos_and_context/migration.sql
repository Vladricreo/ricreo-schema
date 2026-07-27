-- CreateEnum
CREATE TYPE "print-farm"."FeedbackCategory" AS ENUM (
    'PRINT_DEFECT',
    'MATERIAL_DEFECT',
    'WRONG_DIMENSIONS',
    'SUPPORTS_ISSUE',
    'WARPING',
    'MISSING_LAYERS',
    'SLICING_ERROR',
    'OTHER'
);

-- AlterTable
ALTER TABLE "print-farm"."FarmFeedback"
ADD COLUMN "imageUrls" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
ADD COLUMN "category" "print-farm"."FeedbackCategory",
ADD COLUMN "affectedQuantity" INTEGER,
ADD COLUMN "harvestId" UUID,
ADD COLUMN "productionJobId" UUID;

-- Impedisce di superare il limite allegati anche con richieste PATCH concorrenti.
ALTER TABLE "print-farm"."FarmFeedback"
ADD CONSTRAINT "FarmFeedback_imageUrls_max_6"
CHECK (cardinality("imageUrls") <= 6);

-- CreateIndex
CREATE INDEX "FarmFeedback_harvestId_idx"
ON "print-farm"."FarmFeedback"("harvestId");

-- CreateIndex
CREATE INDEX "FarmFeedback_productionJobId_idx"
ON "print-farm"."FarmFeedback"("productionJobId");

-- AddForeignKey
ALTER TABLE "print-farm"."FarmFeedback"
ADD CONSTRAINT "FarmFeedback_harvestId_fkey"
FOREIGN KEY ("harvestId")
REFERENCES "print-farm"."PrinterHarvest"("id")
ON DELETE SET NULL
ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."FarmFeedback"
ADD CONSTRAINT "FarmFeedback_productionJobId_fkey"
FOREIGN KEY ("productionJobId")
REFERENCES "print-farm"."ProductionJob"("id")
ON DELETE SET NULL
ON UPDATE CASCADE;
