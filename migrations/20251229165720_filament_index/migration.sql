/*
  Warnings:

  - You are about to drop the column `sliceFilaments` on the `ProjectThreeMFFile` table. All the data in the column will be lost.
  - A unique constraint covering the columns `[fileId,fileFilamentIndex]` on the table `ProjectFileMaterial` will be added. If there are existing duplicate values, this will fail.

*/
-- DropForeignKey
ALTER TABLE "print-farm"."ProjectFileMaterial" DROP CONSTRAINT "ProjectFileMaterial_materialId_fkey";

-- DropIndex
DROP INDEX "print-farm"."ProjectFileMaterial_fileId_materialId_key";

-- AlterTable
ALTER TABLE "print-farm"."ProjectFileMaterial" ADD COLUMN     "filamentType" TEXT,
ADD COLUMN     "fileFilamentId" TEXT,
ADD COLUMN     "fileFilamentIndex" INTEGER NOT NULL DEFAULT 1,
ADD COLUMN     "trayInfoIdx" TEXT,
ALTER COLUMN "materialId" DROP NOT NULL;

-- Data migration (safe): assegna un indice univoco per fileId alle righe esistenti
-- così la creazione dell'UNIQUE su (fileId, fileFilamentIndex) non fallisce.
WITH ranked AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY "fileId"
      ORDER BY "createdAt" NULLS LAST, id
    ) AS rn
  FROM "print-farm"."ProjectFileMaterial"
)
UPDATE "print-farm"."ProjectFileMaterial" p
SET "fileFilamentIndex" = ranked.rn
FROM ranked
WHERE p.id = ranked.id;

-- CreateIndex
CREATE UNIQUE INDEX "ProjectFileMaterial_fileId_fileFilamentIndex_key" ON "print-farm"."ProjectFileMaterial"("fileId", "fileFilamentIndex");

-- AddForeignKey
ALTER TABLE "print-farm"."ProjectFileMaterial" ADD CONSTRAINT "ProjectFileMaterial_materialId_fkey" FOREIGN KEY ("materialId") REFERENCES "inventory"."Item"("id") ON DELETE SET NULL ON UPDATE CASCADE;
