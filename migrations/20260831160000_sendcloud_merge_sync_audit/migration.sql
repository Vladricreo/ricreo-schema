-- CreateEnum
CREATE TYPE "inventory"."SendcloudParcelOrderRole" AS ENUM ('PRIMARY', 'SECONDARY');

-- CreateEnum
CREATE TYPE "inventory"."SendcloudConsolidationStatus" AS ENUM ('PENDING', 'SUCCESS', 'FAILED', 'SKIPPED');

-- CreateEnum
CREATE TYPE "inventory"."AmazonShipmentConfirmStatus" AS ENUM ('PENDING', 'SUCCESS', 'FAILED', 'SKIPPED');

-- AlterTable
ALTER TABLE "inventory"."SendcloudMergeGroup"
ADD COLUMN IF NOT EXISTS "primaryOrderId" UUID;

-- AlterTable
ALTER TABLE "inventory"."SendcloudParcelOrder"
ADD COLUMN IF NOT EXISTS "role" "inventory"."SendcloudParcelOrderRole" NOT NULL DEFAULT 'PRIMARY',
ADD COLUMN IF NOT EXISTS "orderNumberSnapshot" TEXT,
ADD COLUMN IF NOT EXISTS "marketplaceOrderIdSnapshot" TEXT,
ADD COLUMN IF NOT EXISTS "sendcloudConsolidationStatus" "inventory"."SendcloudConsolidationStatus" NOT NULL DEFAULT 'PENDING',
ADD COLUMN IF NOT EXISTS "sendcloudConsolidationError" TEXT,
ADD COLUMN IF NOT EXISTS "amazonConfirmStatus" "inventory"."AmazonShipmentConfirmStatus" NOT NULL DEFAULT 'PENDING',
ADD COLUMN IF NOT EXISTS "amazonConfirmAttempts" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS "amazonConfirmLastError" TEXT,
ADD COLUMN IF NOT EXISTS "amazonConfirmedAt" TIMESTAMPTZ(6);

-- AddForeignKey
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'SendcloudMergeGroup_primaryOrderId_fkey'
  ) THEN
    ALTER TABLE "inventory"."SendcloudMergeGroup"
    ADD CONSTRAINT "SendcloudMergeGroup_primaryOrderId_fkey"
    FOREIGN KEY ("primaryOrderId")
    REFERENCES "inventory"."SendcloudOrder"("id")
    ON DELETE SET NULL
    ON UPDATE CASCADE;
  END IF;
END $$;

-- CreateIndex
CREATE INDEX IF NOT EXISTS "SendcloudMergeGroup_primaryOrderId_idx"
ON "inventory"."SendcloudMergeGroup"("primaryOrderId");

CREATE INDEX IF NOT EXISTS "SendcloudParcelOrder_amazonConfirmStatus_idx"
ON "inventory"."SendcloudParcelOrder"("amazonConfirmStatus");

CREATE INDEX IF NOT EXISTS "SendcloudParcelOrder_sendcloudConsolidationStatus_idx"
ON "inventory"."SendcloudParcelOrder"("sendcloudConsolidationStatus");
