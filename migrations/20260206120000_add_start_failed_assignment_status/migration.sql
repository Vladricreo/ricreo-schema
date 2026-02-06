-- Aggiunge il valore START_FAILED all'enum AssignmentStatus.
-- START_FAILED = avvio fallito perché la stampante è in errore, serve intervento operatore.
-- Self-healing: quando la stampante esce da ERROR, le assignment START_FAILED
-- vengono automaticamente riportate a QUEUED dal backend (PrintRunLinker).

ALTER TYPE "print-farm"."AssignmentStatus" ADD VALUE IF NOT EXISTS 'START_FAILED';
