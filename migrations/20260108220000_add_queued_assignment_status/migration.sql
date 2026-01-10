-- Aggiunge il valore QUEUED all'enum AssignmentStatus
-- QUEUED = in coda attiva, lo scheduler lo avvia appena c'è budget kW
-- Distinto da SCHEDULED che è solo pianificato e NON parte automaticamente

ALTER TYPE "print-farm"."AssignmentStatus" ADD VALUE IF NOT EXISTS 'QUEUED';
