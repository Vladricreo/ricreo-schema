-- AlterTable
ALTER TABLE "print-farm"."ProjectThreeMFFile" ADD COLUMN     "productPartId" UUID;

-- CreateIndex
CREATE INDEX "ProjectThreeMFFile_productPartId_idx" ON "print-farm"."ProjectThreeMFFile"("productPartId");

-- AddForeignKey
ALTER TABLE "print-farm"."ProjectThreeMFFile" ADD CONSTRAINT "ProjectThreeMFFile_productPartId_fkey" FOREIGN KEY ("productPartId") REFERENCES "inventory"."ProductPart"("id") ON DELETE SET NULL ON UPDATE CASCADE;
