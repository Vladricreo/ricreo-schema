-- AlterTable: Aggiungi default a preferredTags per retrocompatibilità
ALTER TABLE "print-farm"."Printer" ALTER COLUMN "preferredTags" SET DEFAULT ARRAY[]::TEXT[];

-- CreateTable: Tabella M2M per le categorie materiali preferite delle stampanti
CREATE TABLE "print-farm"."PrinterPreferredMaterialCategory" (
    "printerId" UUID NOT NULL,
    "categoryId" UUID NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PrinterPreferredMaterialCategory_pkey" PRIMARY KEY ("printerId","categoryId")
);

-- CreateIndex
CREATE INDEX "PrinterPreferredMaterialCategory_printerId_idx" ON "print-farm"."PrinterPreferredMaterialCategory"("printerId");

-- CreateIndex
CREATE INDEX "PrinterPreferredMaterialCategory_categoryId_idx" ON "print-farm"."PrinterPreferredMaterialCategory"("categoryId");

-- AddForeignKey
ALTER TABLE "print-farm"."PrinterPreferredMaterialCategory" ADD CONSTRAINT "PrinterPreferredMaterialCategory_printerId_fkey" FOREIGN KEY ("printerId") REFERENCES "print-farm"."Printer"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."PrinterPreferredMaterialCategory" ADD CONSTRAINT "PrinterPreferredMaterialCategory_categoryId_fkey" FOREIGN KEY ("categoryId") REFERENCES "inventory"."Category"("id") ON DELETE CASCADE ON UPDATE CASCADE;
