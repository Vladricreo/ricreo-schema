-- Piatti combinati, fase 2 (28/10, R-122/R-123, audits/2026-10-28-piatti-combinati/PIANO.md):
-- oggetti del piatto con parte e posizione, foto dall'alto del piatto. Solo aggiunte.
-- Il backfill dai file esistenti (sliceObjects) è uno script a parte, lanciato dall'utente.
-- AlterTable
ALTER TABLE "print-farm"."ProjectThreeMFFile" ADD COLUMN     "topImageUrl" TEXT;

-- CreateTable
CREATE TABLE "print-farm"."ProjectFileObject" (
    "id" UUID NOT NULL,
    "fileId" UUID NOT NULL,
    "identifyId" INTEGER NOT NULL,
    "name" TEXT,
    "skippedInFile" BOOLEAN NOT NULL DEFAULT false,
    "productPartId" UUID,
    "mappingSource" TEXT,
    "boxCx" DOUBLE PRECISION,
    "boxCy" DOUBLE PRECISION,
    "boxMinX" DOUBLE PRECISION,
    "boxMinY" DOUBLE PRECISION,
    "boxMaxX" DOUBLE PRECISION,
    "boxMaxY" DOUBLE PRECISION,
    "boxArea" DOUBLE PRECISION,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ProjectFileObject_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "ProjectFileObject_productPartId_idx" ON "print-farm"."ProjectFileObject"("productPartId");

-- CreateIndex
CREATE UNIQUE INDEX "ProjectFileObject_fileId_identifyId_key" ON "print-farm"."ProjectFileObject"("fileId", "identifyId");

-- AddForeignKey
ALTER TABLE "print-farm"."ProjectFileObject" ADD CONSTRAINT "ProjectFileObject_fileId_fkey" FOREIGN KEY ("fileId") REFERENCES "print-farm"."ProjectThreeMFFile"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."ProjectFileObject" ADD CONSTRAINT "ProjectFileObject_productPartId_fkey" FOREIGN KEY ("productPartId") REFERENCES "inventory"."ProductPart"("id") ON DELETE SET NULL ON UPDATE CASCADE;

