/*
  Warnings:

  - Made the column `materialSpecId` on table `ProductPartMaterial` required. This step will fail if there are existing NULL values in that column.

*/
-- CreateEnum
CREATE TYPE "print-farm"."PrinterMacroCategory" AS ENUM ('GENERIC', 'UNLOAD_FILAMENT', 'LOAD_FILAMENT', 'BRIGHT_COLOR_START', 'CLEANING', 'CALIBRATION', 'MAINTENANCE', 'TEST_GENERAL');

-- AlterTable
ALTER TABLE "inventory"."ProductPartMaterial" ALTER COLUMN "materialSpecId" SET NOT NULL;

-- AlterTable
ALTER TABLE "print-farm"."PrinterMacro" ADD COLUMN     "category" "print-farm"."PrinterMacroCategory" NOT NULL DEFAULT 'GENERIC';

-- CreateIndex
CREATE INDEX "PrinterMacro_category_idx" ON "print-farm"."PrinterMacro"("category");
