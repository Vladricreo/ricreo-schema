-- AlterTable
ALTER TABLE "print-farm"."PrintFarmNotificationPreference" ALTER COLUMN "id" DROP DEFAULT;

-- CreateIndex
CREATE INDEX "PrinterAmsSlot_spoolId_idx" ON "print-farm"."PrinterAmsSlot"("spoolId");
