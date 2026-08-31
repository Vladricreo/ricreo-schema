-- AlterTable
ALTER TABLE "inventory"."SendcloudOrder" ADD COLUMN IF NOT EXISTS "carrierShippingCost" DECIMAL(12,2);
ALTER TABLE "inventory"."SendcloudOrder" ADD COLUMN IF NOT EXISTS "carrierShippingCurrency" VARCHAR(3);
