-- Migrazione: Rinomina FarmProductionStatus.COMPLETED in FULFILLED
-- Per maggiore chiarezza rispetto a AssignmentStatus.COMPLETED

-- Step 1: Aggiungi nuovo valore
ALTER TYPE "print-farm"."FarmProductionStatus" ADD VALUE IF NOT EXISTS 'FULFILLED';
