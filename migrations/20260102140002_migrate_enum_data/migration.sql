-- Step 2: Migrare dati esistenti ai nuovi valori enum
-- I valori sono stati aggiunti nella migrazione precedente e sono ora disponibili.

-- AssignmentStatus: UNLOADED -> HARVESTED
UPDATE "print-farm"."PrinterAssignment" 
SET status = 'HARVESTED' 
WHERE status = 'UNLOADED';

-- AssignmentStatus: TO_LOAD -> QUEUED (rimuoviamo TO_LOAD, torna in coda)
UPDATE "print-farm"."PrinterAssignment" 
SET status = 'QUEUED' 
WHERE status = 'TO_LOAD';

-- PrinterOperationalStatus: TO_LOAD -> NEEDS_SETUP
UPDATE "print-farm"."Printer" 
SET "operationalStatus" = 'NEEDS_SETUP' 
WHERE "operationalStatus" = 'TO_LOAD';

-- Nota: PostgreSQL non supporta DROP VALUE su enum esistenti senza ricreare il tipo.
-- I vecchi valori (UNLOADED, TO_LOAD) restano nell'enum ma non vengono più usati.
