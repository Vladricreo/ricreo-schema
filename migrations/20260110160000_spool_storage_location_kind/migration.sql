-- Aggiunge SPOOL_STORAGE all'enum WarehouseLocationKind
-- Per area dedicata allo stoccaggio di bobine parzialmente usate

ALTER TYPE "inventory"."WarehouseLocationKind" ADD VALUE 'SPOOL_STORAGE';
