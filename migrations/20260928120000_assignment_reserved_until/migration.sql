-- Prenotazione UI delle assignment aperte nel dialog "Avvia stampe".
-- Finché reservedUntil è nel futuro lo scheduler non riassegna né cancella la riga.
ALTER TABLE "print-farm"."PrinterAssignment"
  ADD COLUMN "reservedUntil" TIMESTAMPTZ(6);
