-- Pausa per inserimento aggiuntivo (17/11): ora in cui la prima pausa è stata registrata.
-- Prima solo lo schermo che arrivava primo (TV o pagina Produzione) riceveva
-- `isFirst` e diceva «in pausa per inserimento»; gli altri, kiosk compreso, solo
-- «in pausa». Con l'ora salvata la route risponde `isFirst` a ogni schermo che
-- chiama entro 10 minuti dalla prima registrazione.
--
-- Additiva e idempotente: colonna nullable, nessun dato esistente toccato.

ALTER TABLE "print-farm"."PrinterAssignment"
  ADD COLUMN IF NOT EXISTS "insertPauseNoticeAt" TIMESTAMPTZ(6);

COMMENT ON COLUMN "print-farm"."PrinterAssignment"."insertPauseNoticeAt"
  IS 'Ora in cui è stata registrata la prima pausa per inserimento aggiuntivo di questa assegnazione (finestra di 10 minuti per tutti gli schermi).';
