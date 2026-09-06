-- Aggiunge flag isManual a ProductOrder.
-- Gli ordini manuali non vengono modificati dalla generazione automatica
-- (priorità e quantità restano quelli impostati dall'utente).
ALTER TABLE inventory."ProductOrder"
  ADD COLUMN IF NOT EXISTS "isManual" BOOLEAN NOT NULL DEFAULT false;
