-- Cleanup: rimuove valori enum obsoleti che non sono più usati
-- Questa migration viene DOPO tutte le data migration che hanno migrato i dati verso i nuovi valori.
--
-- PostgreSQL non supporta DROP VALUE su enum, quindi si ricrea l'enum.
--
-- Nota: CupsPrintJobKind è stato spostato in 20260108201550_sync_schema_updates
-- perché deve esistere PRIMA della creazione di CupsPrintProfile

-- ============================================================================
-- AssignmentStatus: rimuove QUEUED, READY, TO_LOAD, UNLOADED, HARVESTED
-- Stato attuale dopo le migration precedenti:
--   QUEUED, READY, TO_LOAD, PRINTING, COMPLETED, UNLOADED, FAILED, CANCELLED, HARVESTED, SCHEDULED, TO_HARVEST
-- Stato finale desiderato:
--   SCHEDULED, PRINTING, TO_HARVEST, COMPLETED, FAILED, CANCELLED
-- ============================================================================

-- Step 1: Crea nuovo tipo con solo i valori attuali
CREATE TYPE "print-farm"."AssignmentStatus_new" AS ENUM (
  'SCHEDULED',
  'PRINTING',
  'TO_HARVEST',
  'COMPLETED',
  'FAILED',
  'CANCELLED'
);

-- Step 2: Alter column per usare il nuovo tipo
ALTER TABLE "print-farm"."PrinterAssignment" 
  ALTER COLUMN status DROP DEFAULT;

ALTER TABLE "print-farm"."PrinterAssignment" 
  ALTER COLUMN status TYPE "print-farm"."AssignmentStatus_new" 
  USING (status::text::"print-farm"."AssignmentStatus_new");

-- Step 3: Drop old, rename new
DROP TYPE "print-farm"."AssignmentStatus";
ALTER TYPE "print-farm"."AssignmentStatus_new" RENAME TO "AssignmentStatus";

-- Step 4: Set default to SCHEDULED
ALTER TABLE "print-farm"."PrinterAssignment" 
  ALTER COLUMN status SET DEFAULT 'SCHEDULED'::"print-farm"."AssignmentStatus";

-- ============================================================================
-- FarmProductionStatus: rimuove COMPLETED (sostituito da FULFILLED)
-- Stato attuale dopo le migration precedenti:
--   READY_TO_PRODUCE, NEEDS_CONFIGURATION, AWAITING_RESOURCES, IN_PROGRESS, COMPLETED, FAILED, FULFILLED
-- Stato finale desiderato:
--   READY_TO_PRODUCE, NEEDS_CONFIGURATION, AWAITING_RESOURCES, IN_PROGRESS, FULFILLED, FAILED
-- ============================================================================

-- Step 1: Crea nuovo tipo senza COMPLETED
CREATE TYPE "print-farm"."FarmProductionStatus_new" AS ENUM (
  'READY_TO_PRODUCE',
  'NEEDS_CONFIGURATION',
  'AWAITING_RESOURCES',
  'IN_PROGRESS',
  'FULFILLED',
  'FAILED'
);

-- Step 2: Alter column
ALTER TABLE "print-farm"."ProductionJob" 
  ALTER COLUMN status DROP DEFAULT;

ALTER TABLE "print-farm"."ProductionJob" 
  ALTER COLUMN status TYPE "print-farm"."FarmProductionStatus_new" 
  USING (status::text::"print-farm"."FarmProductionStatus_new");

-- Step 3: Drop old, rename new
DROP TYPE "print-farm"."FarmProductionStatus";
ALTER TYPE "print-farm"."FarmProductionStatus_new" RENAME TO "FarmProductionStatus";

-- Step 4: Ripristina default
ALTER TABLE "print-farm"."ProductionJob" 
  ALTER COLUMN status SET DEFAULT 'READY_TO_PRODUCE'::"print-farm"."FarmProductionStatus";
