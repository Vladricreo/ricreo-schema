-- Add isBedHeating flag to Printer (print-farm schema)
-- Motivo:
-- - Stato indipendente da operationalStatus (una stampante può essere PRINTING ma con bed in riscaldamento)
-- - Serve per analytics/consumi e per distinguere fase peakPower (heating) vs runPower (steady)

ALTER TABLE "print-farm"."Printer"
ADD COLUMN IF NOT EXISTS "isBedHeating" boolean NOT NULL DEFAULT false;

-- Backfill safety (nel caso DB già abbia NULL per qualche motivo)
UPDATE "print-farm"."Printer"
SET "isBedHeating" = false
WHERE "isBedHeating" IS NULL;

