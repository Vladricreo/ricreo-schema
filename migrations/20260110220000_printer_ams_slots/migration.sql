-- Crea tabella PrinterAmsSlot per tracciare le spool in ogni slot AMS
-- Ogni stampante con AMS può avere fino a 4 unità (A-D) x 4 slot ciascuna

-- CreateTable
CREATE TABLE "print-farm"."PrinterAmsSlot" (
    "id" UUID NOT NULL,
    "printerId" UUID NOT NULL,
    "amsUnit" INTEGER NOT NULL,
    "slot" INTEGER NOT NULL,
    "spoolId" UUID,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PrinterAmsSlot_pkey" PRIMARY KEY ("id")
);

-- CreateIndex: unico per stampante + unità + slot
CREATE UNIQUE INDEX "PrinterAmsSlot_printerId_amsUnit_slot_key" ON "print-farm"."PrinterAmsSlot"("printerId", "amsUnit", "slot");

-- CreateIndex: ricerca per stampante
CREATE INDEX "PrinterAmsSlot_printerId_idx" ON "print-farm"."PrinterAmsSlot"("printerId");

-- CreateIndex: ricerca per spool (per trovare in quale slot è una determinata spool)
CREATE INDEX "PrinterAmsSlot_spoolId_idx" ON "print-farm"."PrinterAmsSlot"("spoolId");

-- CreateIndex: una spool può stare in un solo slot alla volta
CREATE UNIQUE INDEX "PrinterAmsSlot_spoolId_key" ON "print-farm"."PrinterAmsSlot"("spoolId");

-- AddForeignKey: riferimento a Printer
ALTER TABLE "print-farm"."PrinterAmsSlot" ADD CONSTRAINT "PrinterAmsSlot_printerId_fkey" 
FOREIGN KEY ("printerId") REFERENCES "print-farm"."Printer"("id") 
ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey: riferimento a FilamentSpool (nullable)
ALTER TABLE "print-farm"."PrinterAmsSlot" ADD CONSTRAINT "PrinterAmsSlot_spoolId_fkey" 
FOREIGN KEY ("spoolId") REFERENCES "print-farm"."FilamentSpool"("id") 
ON DELETE SET NULL ON UPDATE CASCADE;
