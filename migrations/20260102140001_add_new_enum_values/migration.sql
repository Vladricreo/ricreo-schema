-- Step 1: Aggiungere nuovi valori enum
-- IMPORTANTE: PostgreSQL richiede che i nuovi valori siano committati prima di essere usati.
-- Questa migrazione aggiunge solo i valori, la migrazione successiva li userà.

-- AssignmentStatus: aggiunge HARVESTED
ALTER TYPE "print-farm"."AssignmentStatus" ADD VALUE IF NOT EXISTS 'HARVESTED';

-- PrinterOperationalStatus: aggiunge NEEDS_SETUP e FILAMENT_RUNOUT
ALTER TYPE "print-farm"."PrinterOperationalStatus" ADD VALUE IF NOT EXISTS 'NEEDS_SETUP';
ALTER TYPE "print-farm"."PrinterOperationalStatus" ADD VALUE IF NOT EXISTS 'FILAMENT_RUNOUT';
