-- Migrazione Step 2: Migra dati esistenti COMPLETED -> FULFILLED
-- per FarmProductionStatus (solo ProductionJob)

-- Migra ProductionJob
UPDATE "print-farm"."ProductionJob" 
SET status = 'FULFILLED' 
WHERE status = 'COMPLETED';

-- Nota: ProductOrder è nello schema "inventory" e usa ProductionStatus, non FarmProductionStatus
