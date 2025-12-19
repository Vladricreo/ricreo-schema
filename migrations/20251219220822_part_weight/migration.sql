/*
  Warnings:

  - You are about to drop the column `weight` on the `ProductPart` table. All the data in the column will be lost.

*/
-- AlterTable
ALTER TABLE "inventory"."ProductPart" DROP COLUMN "weight";

-- CreateTable
CREATE TABLE "inventory"."ProductPartMaterial" (
    "id" UUID NOT NULL,
    "productPartId" UUID NOT NULL,
    "materialId" UUID NOT NULL,
    "usedWeight" DECIMAL(12,3) NOT NULL DEFAULT 0,
    "notes" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ProductPartMaterial_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "ProductPartMaterial_productPartId_idx" ON "inventory"."ProductPartMaterial"("productPartId");

-- CreateIndex
CREATE INDEX "ProductPartMaterial_materialId_idx" ON "inventory"."ProductPartMaterial"("materialId");

-- CreateIndex
CREATE UNIQUE INDEX "ProductPartMaterial_productPartId_materialId_key" ON "inventory"."ProductPartMaterial"("productPartId", "materialId");

-- AddForeignKey
ALTER TABLE "inventory"."ProductPartMaterial" ADD CONSTRAINT "ProductPartMaterial_productPartId_fkey" FOREIGN KEY ("productPartId") REFERENCES "inventory"."ProductPart"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."ProductPartMaterial" ADD CONSTRAINT "ProductPartMaterial_materialId_fkey" FOREIGN KEY ("materialId") REFERENCES "inventory"."Item"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
