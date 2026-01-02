-- Migrazione Step 2: Migra dati esistenti verso nuovi stati AssignmentStatus
--
-- Mapping:
--   QUEUED, READY → SCHEDULED
--   COMPLETED → TO_HARVEST (stampa finita, da scaricare)
--   HARVESTED → COMPLETED (tutto fatto)
--
-- NOTA: I vecchi valori (QUEUED, READY, HARVESTED) restano nell'enum PostgreSQL
-- ma non verranno più usati dal codice.

-- Migra QUEUED e READY → SCHEDULED
UPDATE "print-farm"."PrinterAssignment" 
SET status = 'SCHEDULED' 
WHERE status IN ('QUEUED', 'READY');

-- Migra COMPLETED → TO_HARVEST (prima del prossimo, perché COMPLETED viene riusato)
UPDATE "print-farm"."PrinterAssignment" 
SET status = 'TO_HARVEST' 
WHERE status = 'COMPLETED';

-- Migra HARVESTED → COMPLETED
UPDATE "print-farm"."PrinterAssignment" 
SET status = 'COMPLETED' 
WHERE status = 'HARVESTED';
