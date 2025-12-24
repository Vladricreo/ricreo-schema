/*
  Warnings:

  - Made the column `leadTime` on table `Supplier` required. This step will fail if there are existing NULL values in that column.

*/
-- AlterEnum
ALTER TYPE "inventory"."SettingsName" ADD VALUE 'SHIPMENTS_SYNC_DAYS';

-- AlterTable
ALTER TABLE "inventory"."Supplier" ALTER COLUMN "leadTime" SET NOT NULL,
ALTER COLUMN "leadTime" SET DEFAULT 7;
