-- Rende opzionale l'odette nello scarico (PrinterHarvest).
-- Obiettivo: permettere l'harvest anche quando non esiste un contenitore disponibile.

-- 1) Rimuovi FK attuale (ON DELETE RESTRICT) per poterla ricreare con SET NULL
ALTER TABLE "print-farm"."PrinterHarvest"
DROP CONSTRAINT "PrinterHarvest_odetteId_fkey";

-- 2) Rendi nullable la colonna
ALTER TABLE "print-farm"."PrinterHarvest"
ALTER COLUMN "odetteId" DROP NOT NULL;

-- 3) Ricrea la FK con ON DELETE SET NULL
ALTER TABLE "print-farm"."PrinterHarvest"
ADD CONSTRAINT "PrinterHarvest_odetteId_fkey"
FOREIGN KEY ("odetteId") REFERENCES "inventory"."Odette"("id")
ON DELETE SET NULL ON UPDATE CASCADE;

