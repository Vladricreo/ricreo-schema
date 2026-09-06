-- Aggiunge i campi necessari per la funzionalità "Pausa per inserimento aggiuntivo":
-- - ProjectThreeMFFile.requiresAdditionalInsert: flag sul file che richiede un intervento
--   manuale a metà stampa (es. inserimento di un componente/inserto).
-- - PrinterAssignment.insertPauseNoticeShown: traccia se all'operatore è già stata mostrata
--   la notifica dedicata per la prima pausa di questa assegnazione.
--
-- Additiva e idempotente: ADD COLUMN IF NOT EXISTS con default, nessun impatto sui dati esistenti.

ALTER TABLE "print-farm"."ProjectThreeMFFile"
  ADD COLUMN IF NOT EXISTS "requiresAdditionalInsert" BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN "print-farm"."ProjectThreeMFFile"."requiresAdditionalInsert"
  IS 'Il file richiede un intervento manuale a metà stampa (es. inserimento di un componente/inserto) che causa una pausa attesa.';

ALTER TABLE "print-farm"."PrinterAssignment"
  ADD COLUMN IF NOT EXISTS "insertPauseNoticeShown" BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN "print-farm"."PrinterAssignment"."insertPauseNoticeShown"
  IS 'Traccia se all''operatore è già stata mostrata la notifica "Pausa per inserimento aggiuntivo" per la prima pausa di questa assegnazione.';
