-- CreateEnum
CREATE TYPE "print-farm"."SupplyVoltage" AS ENUM ('V110', 'V220');

-- CreateEnum
CREATE TYPE "print-farm"."EnergyPhaseKey" AS ENUM ('STANDBY_OFFLINE', 'STANDBY_ONLINE', 'PRINT_HEAT', 'PRINT_RUN');

-- CreateEnum
CREATE TYPE "print-farm"."AmsModel" AS ENUM ('AMS', 'AMS_LITE', 'AMS_2_PRO', 'AMS_HT');

-- CreateEnum
CREATE TYPE "print-farm"."AmsPhaseKey" AS ENUM ('STANDBY', 'WORKING', 'DRYING');

-- AlterTable
ALTER TABLE "print-farm"."Printer" ADD COLUMN     "amsModel" "print-farm"."AmsModel";

-- CreateTable
CREATE TABLE "print-farm"."PrinterModelEnergyProfile" (
    "id" UUID NOT NULL,
    "printerModelId" INTEGER NOT NULL,
    "voltage" "print-farm"."SupplyVoltage" NOT NULL,
    "phase" "print-farm"."EnergyPhaseKey" NOT NULL,
    "materialCategoryId" UUID,
    "powerW" DECIMAL(12,3) NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PrinterModelEnergyProfile_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "print-farm"."AmsEnergyProfile" (
    "id" SERIAL NOT NULL,
    "amsModel" "print-farm"."AmsModel" NOT NULL,
    "phase" "print-farm"."AmsPhaseKey" NOT NULL,
    "powerW" DECIMAL(12,3) NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AmsEnergyProfile_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "print-farm"."PrinterEnergyDailySlice" (
    "id" UUID NOT NULL,
    "day" DATE NOT NULL,
    "printerId" UUID NOT NULL,
    "phase" "print-farm"."EnergyPhaseKey" NOT NULL,
    "materialCategoryId" UUID,
    "kwh" DECIMAL(12,6) NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PrinterEnergyDailySlice_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "PrinterModelEnergyProfile_printerModelId_idx" ON "print-farm"."PrinterModelEnergyProfile"("printerModelId");

-- CreateIndex
CREATE INDEX "PrinterModelEnergyProfile_materialCategoryId_idx" ON "print-farm"."PrinterModelEnergyProfile"("materialCategoryId");

-- CreateIndex
CREATE INDEX "PrinterModelEnergyProfile_voltage_phase_idx" ON "print-farm"."PrinterModelEnergyProfile"("voltage", "phase");

-- CreateIndex
CREATE UNIQUE INDEX "PrinterModelEnergyProfile_printerModelId_voltage_phase_mate_key" ON "print-farm"."PrinterModelEnergyProfile"("printerModelId", "voltage", "phase", "materialCategoryId");

-- CreateIndex
CREATE INDEX "AmsEnergyProfile_amsModel_idx" ON "print-farm"."AmsEnergyProfile"("amsModel");

-- CreateIndex
CREATE UNIQUE INDEX "AmsEnergyProfile_amsModel_phase_key" ON "print-farm"."AmsEnergyProfile"("amsModel", "phase");

-- CreateIndex
CREATE INDEX "PrinterEnergyDailySlice_day_idx" ON "print-farm"."PrinterEnergyDailySlice"("day");

-- CreateIndex
CREATE INDEX "PrinterEnergyDailySlice_printerId_idx" ON "print-farm"."PrinterEnergyDailySlice"("printerId");

-- CreateIndex
CREATE INDEX "PrinterEnergyDailySlice_phase_idx" ON "print-farm"."PrinterEnergyDailySlice"("phase");

-- CreateIndex
CREATE INDEX "PrinterEnergyDailySlice_materialCategoryId_idx" ON "print-farm"."PrinterEnergyDailySlice"("materialCategoryId");

-- CreateIndex
CREATE UNIQUE INDEX "PrinterEnergyDailySlice_day_printerId_phase_materialCategor_key" ON "print-farm"."PrinterEnergyDailySlice"("day", "printerId", "phase", "materialCategoryId");

-- AddForeignKey
ALTER TABLE "print-farm"."PrinterModelEnergyProfile" ADD CONSTRAINT "PrinterModelEnergyProfile_printerModelId_fkey" FOREIGN KEY ("printerModelId") REFERENCES "print-farm"."PrinterModel"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."PrinterModelEnergyProfile" ADD CONSTRAINT "PrinterModelEnergyProfile_materialCategoryId_fkey" FOREIGN KEY ("materialCategoryId") REFERENCES "inventory"."Category"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."PrinterEnergyDailySlice" ADD CONSTRAINT "PrinterEnergyDailySlice_printerId_fkey" FOREIGN KEY ("printerId") REFERENCES "print-farm"."Printer"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."PrinterEnergyDailySlice" ADD CONSTRAINT "PrinterEnergyDailySlice_materialCategoryId_fkey" FOREIGN KEY ("materialCategoryId") REFERENCES "inventory"."Category"("id") ON DELETE SET NULL ON UPDATE CASCADE;
