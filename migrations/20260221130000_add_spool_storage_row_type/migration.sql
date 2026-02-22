-- Aggiunge SPOOL_STORAGE all'enum WarehouseRowType
-- Per permettere un tipo riga dedicato alle bobine aperte

ALTER TYPE "inventory"."WarehouseRowType" ADD VALUE 'SPOOL_STORAGE';
