-- Aggiunge la colonna maxStock alla tabella Sku.
-- 0 = nessun limite (default), coerente con minStock.

ALTER TABLE inventory."Sku"
  ADD COLUMN IF NOT EXISTS "maxStock" INTEGER NOT NULL DEFAULT 0;
