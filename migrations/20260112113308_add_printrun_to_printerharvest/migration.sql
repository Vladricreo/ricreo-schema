-- AlterTable
ALTER TABLE "print-farm"."PrinterHarvest" ADD COLUMN     "printRunId" UUID;

-- CreateIndex
CREATE INDEX "PrinterHarvest_printRunId_idx" ON "print-farm"."PrinterHarvest"("printRunId");

-- AddForeignKey
ALTER TABLE "print-farm"."PrinterHarvest" ADD CONSTRAINT "PrinterHarvest_printRunId_fkey" FOREIGN KEY ("printRunId") REFERENCES "print-farm"."PrintRun"("id") ON DELETE SET NULL ON UPDATE CASCADE;
