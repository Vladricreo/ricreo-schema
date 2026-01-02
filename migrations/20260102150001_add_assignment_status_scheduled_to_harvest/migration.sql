-- Migrazione Step 1: Aggiunge nuovi valori enum per AssignmentStatus
-- SCHEDULED = ex QUEUED (assignment creato, in attesa)
-- TO_HARVEST = ex COMPLETED (stampa finita, da scaricare)

-- Aggiungi SCHEDULED
ALTER TYPE "print-farm"."AssignmentStatus" ADD VALUE IF NOT EXISTS 'SCHEDULED';

-- Aggiungi TO_HARVEST
ALTER TYPE "print-farm"."AssignmentStatus" ADD VALUE IF NOT EXISTS 'TO_HARVEST';
