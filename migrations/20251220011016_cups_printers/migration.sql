-- CreateEnum
CREATE TYPE "inventory"."CupsPrinterKind" AS ENUM ('LABEL', 'SHEET');

-- CreateEnum
CREATE TYPE "inventory"."CupsLabelOrientation" AS ENUM ('PORTRAIT', 'LANDSCAPE');

-- CreateTable
CREATE TABLE "inventory"."CupsPrinter" (
    "id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "cupsName" TEXT NOT NULL,
    "cupsServerUrl" TEXT,
    "kind" "inventory"."CupsPrinterKind" NOT NULL DEFAULT 'LABEL',
    "imageUrl" TEXT,
    "description" TEXT,
    "location" TEXT,
    "isDefault" BOOLEAN NOT NULL DEFAULT false,
    "isArchived" BOOLEAN NOT NULL DEFAULT false,
    "supportsColor" BOOLEAN NOT NULL DEFAULT false,
    "preferredDpi" INTEGER,
    "defaultJobOptions" JSONB NOT NULL DEFAULT '{}',
    "defaultLabelFormatId" UUID,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CupsPrinter_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."CupsLabelFormat" (
    "id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "widthMm" DECIMAL(8,2) NOT NULL,
    "heightMm" DECIMAL(8,2) NOT NULL,
    "gapMm" DECIMAL(8,2),
    "marginTopMm" DECIMAL(8,2),
    "marginRightMm" DECIMAL(8,2),
    "marginBottomMm" DECIMAL(8,2),
    "marginLeftMm" DECIMAL(8,2),
    "orientation" "inventory"."CupsLabelOrientation" NOT NULL DEFAULT 'PORTRAIT',
    "cupsMediaName" TEXT,
    "jobOptions" JSONB NOT NULL DEFAULT '{}',
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CupsLabelFormat_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."_PrinterLabelFormats" (
    "A" UUID NOT NULL,
    "B" UUID NOT NULL,

    CONSTRAINT "_PrinterLabelFormats_AB_pkey" PRIMARY KEY ("A","B")
);

-- CreateIndex
CREATE UNIQUE INDEX "CupsPrinter_cupsName_key" ON "inventory"."CupsPrinter"("cupsName");

-- CreateIndex
CREATE INDEX "CupsPrinter_kind_idx" ON "inventory"."CupsPrinter"("kind");

-- CreateIndex
CREATE INDEX "CupsPrinter_isArchived_idx" ON "inventory"."CupsPrinter"("isArchived");

-- CreateIndex
CREATE INDEX "CupsPrinter_isDefault_idx" ON "inventory"."CupsPrinter"("isDefault");

-- CreateIndex
CREATE UNIQUE INDEX "CupsLabelFormat_name_key" ON "inventory"."CupsLabelFormat"("name");

-- CreateIndex
CREATE INDEX "_PrinterLabelFormats_B_index" ON "inventory"."_PrinterLabelFormats"("B");

-- AddForeignKey
ALTER TABLE "inventory"."CupsPrinter" ADD CONSTRAINT "CupsPrinter_defaultLabelFormatId_fkey" FOREIGN KEY ("defaultLabelFormatId") REFERENCES "inventory"."CupsLabelFormat"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."_PrinterLabelFormats" ADD CONSTRAINT "_PrinterLabelFormats_A_fkey" FOREIGN KEY ("A") REFERENCES "inventory"."CupsLabelFormat"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."_PrinterLabelFormats" ADD CONSTRAINT "_PrinterLabelFormats_B_fkey" FOREIGN KEY ("B") REFERENCES "inventory"."CupsPrinter"("id") ON DELETE CASCADE ON UPDATE CASCADE;
