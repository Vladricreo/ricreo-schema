-- Aggiunge l'odette pianificata di destinazione per le righe REUSABLE.
-- Viene scelta in fase di ricezione e usata poi dal flusso di Riassemblaggio
-- per registrare il movimento RESO_IN nell'odette corretta.

ALTER TABLE inventory."CustomerReturnLine"
  ADD COLUMN "targetOdetteId" UUID;

CREATE INDEX "CustomerReturnLine_targetOdetteId_idx"
  ON inventory."CustomerReturnLine"("targetOdetteId");

ALTER TABLE inventory."CustomerReturnLine"
  ADD CONSTRAINT "CustomerReturnLine_targetOdetteId_fkey"
  FOREIGN KEY ("targetOdetteId")
  REFERENCES inventory."Odette"("id")
  ON DELETE SET NULL
  ON UPDATE CASCADE;
