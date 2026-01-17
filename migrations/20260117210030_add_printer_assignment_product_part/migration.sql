-- AlterTable
ALTER TABLE "print-farm"."PrinterAssignment" ADD COLUMN     "productPartId" UUID;

-- CreateIndex
CREATE INDEX "PrinterAssignment_productPartId_idx" ON "print-farm"."PrinterAssignment"("productPartId");

-- AddForeignKey
ALTER TABLE "print-farm"."PrinterAssignment" ADD CONSTRAINT "PrinterAssignment_productPartId_fkey" FOREIGN KEY ("productPartId") REFERENCES "inventory"."ProductPart"("id") ON DELETE SET NULL ON UPDATE CASCADE;
