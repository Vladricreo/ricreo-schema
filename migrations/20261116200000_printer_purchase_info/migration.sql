-- A-406 (16/11): scheda acquisto della stampante per lo storico manutenzioni.
-- Colonne nuove, tutte facoltative: nessun dato esistente cambia.
ALTER TABLE "print-farm"."Printer"
  ADD COLUMN IF NOT EXISTS "purchasedAt" DATE,
  ADD COLUMN IF NOT EXISTS "purchasePrice" DECIMAL(12,2),
  ADD COLUMN IF NOT EXISTS "purchaseSupplier" VARCHAR(200),
  ADD COLUMN IF NOT EXISTS "purchaseInvoiceKey" TEXT,
  ADD COLUMN IF NOT EXISTS "purchaseInvoiceName" VARCHAR(255),
  ADD COLUMN IF NOT EXISTS "purchaseInvoiceAt" TIMESTAMPTZ(6);
