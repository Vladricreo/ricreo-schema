-- DropIndex
DROP INDEX "inventory"."ProductPartMaterial_productPartId_priority_idx";

-- DropIndex
DROP INDEX "inventory"."ProductToComponent_productId_priority_idx";

-- DropIndex
DROP INDEX "inventory"."ProductToPackage_productId_priority_idx";

-- DropIndex
DROP INDEX "inventory"."ProductToUtility_productId_priority_idx";

-- AlterTable
ALTER TABLE "inventory"."ProductToComponent" ADD COLUMN     "assemblyStageId" UUID,
ADD COLUMN     "skuId" UUID,
ALTER COLUMN "id" DROP DEFAULT;

-- AlterTable
ALTER TABLE "inventory"."ProductToPackage" ADD COLUMN     "assemblyStageId" UUID,
ADD COLUMN     "skuId" UUID,
ALTER COLUMN "id" DROP DEFAULT;

-- AlterTable
ALTER TABLE "inventory"."ProductToUtility" ADD COLUMN     "skuId" UUID,
ALTER COLUMN "id" DROP DEFAULT;

-- CreateIndex
CREATE INDEX "ProductToComponent_skuId_idx" ON "inventory"."ProductToComponent"("skuId");

-- CreateIndex
CREATE INDEX "ProductToComponent_assemblyStageId_idx" ON "inventory"."ProductToComponent"("assemblyStageId");

-- CreateIndex
CREATE INDEX "ProductToPackage_skuId_idx" ON "inventory"."ProductToPackage"("skuId");

-- CreateIndex
CREATE INDEX "ProductToPackage_assemblyStageId_idx" ON "inventory"."ProductToPackage"("assemblyStageId");

-- CreateIndex
CREATE INDEX "ProductToUtility_skuId_idx" ON "inventory"."ProductToUtility"("skuId");

-- AddForeignKey
ALTER TABLE "inventory"."ProductToPackage" ADD CONSTRAINT "ProductToPackage_skuId_fkey" FOREIGN KEY ("skuId") REFERENCES "inventory"."Sku"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."ProductToPackage" ADD CONSTRAINT "ProductToPackage_assemblyStageId_fkey" FOREIGN KEY ("assemblyStageId") REFERENCES "inventory"."AssemblyStage"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."ProductToUtility" ADD CONSTRAINT "ProductToUtility_skuId_fkey" FOREIGN KEY ("skuId") REFERENCES "inventory"."Sku"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."ProductToComponent" ADD CONSTRAINT "ProductToComponent_skuId_fkey" FOREIGN KEY ("skuId") REFERENCES "inventory"."Sku"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."ProductToComponent" ADD CONSTRAINT "ProductToComponent_assemblyStageId_fkey" FOREIGN KEY ("assemblyStageId") REFERENCES "inventory"."AssemblyStage"("id") ON DELETE SET NULL ON UPDATE CASCADE;
