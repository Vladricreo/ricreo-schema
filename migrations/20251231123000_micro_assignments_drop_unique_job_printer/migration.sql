-- Migration: abilita micro-assignments (1 run = 1 assignment)
-- Obiettivo: permettere più PrinterAssignment per la stessa coppia (productionJobId, printerId)
--            rimuovendo il vincolo/indice UNIQUE esistente.

-- Drop UNIQUE index creato in precedenza da @@unique([productionJobId, printerId])
DROP INDEX IF EXISTS "print-farm"."PrinterAssignment_productionJobId_printerId_key";

-- Aggiungiamo un indice NON-UNIQUE per mantenere performance su lookup per job+stampante
CREATE INDEX IF NOT EXISTS "PrinterAssignment_productionJobId_printerId_idx"
ON "print-farm"."PrinterAssignment" ("productionJobId", "printerId");


