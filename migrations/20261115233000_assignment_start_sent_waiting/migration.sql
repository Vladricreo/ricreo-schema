-- P-20 e P-22 (giro 4 del confronto Bambuddy, 15/11), PrinterAssignment.
--
-- P-20 `startSentAt`: il backend lo scrive subito prima di mandare `project_file`.
-- Dopo un riavvio del backend una riga QUEUED con `startSentAt` più vecchio
-- dell'avvio del processo non viene rimandata in automatico: con la stampante
-- ferma diventa START_FAILED «inviato prima del riavvio, esito sconosciuto».
-- Prima l'unica traccia era `claimedAt`, che scade dopo 5 minuti, e l'invio
-- poteva ripartire su un piatto non scaricato.
--
-- P-22 `waitingReason` / `waitingSince`: perché una QUEUED non parte, scritto
-- dallo scheduler solo quando il motivo cambia.
--
-- Il trigger azzera le tre colonne a ogni cambio di `status`, con qualunque
-- scrittore (client, backend, altre app sul DB condiviso): una riga rimessa in
-- coda riparte pulita.
--
-- Colonne nullable, nessun dato esistente toccato. Va applicata PRIMA del deploy
-- del client: Prisma legge tutte le colonne scalari dell'assignment. Il backend
-- funziona anche senza (legge con to_jsonb e ignora l'errore 42703 in scrittura).

ALTER TABLE "print-farm"."PrinterAssignment"
  ADD COLUMN "startSentAt" TIMESTAMPTZ(6),
  ADD COLUMN "waitingReason" TEXT,
  ADD COLUMN "waitingSince" TIMESTAMPTZ(6);

CREATE OR REPLACE FUNCTION "print-farm".pf_assignment_clear_start_markers_trg()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    NEW."startSentAt" := NULL;
    NEW."waitingReason" := NULL;
    NEW."waitingSince" := NULL;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER "PrinterAssignment_clear_start_markers"
BEFORE UPDATE OF status ON "print-farm"."PrinterAssignment"
FOR EACH ROW
EXECUTE FUNCTION "print-farm".pf_assignment_clear_start_markers_trg();
