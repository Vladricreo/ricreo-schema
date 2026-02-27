-- Add lastPrint* persistence columns to Printer (print-farm schema)
-- Motivo:
-- - Il backend salva l'ultimo job avviato per consentire la funzione "reprint"
-- - In assenza di queste colonne, il backend degrada a "solo in memoria" e stampa un warning

ALTER TABLE "print-farm"."Printer"
  ADD COLUMN IF NOT EXISTS "lastPrintFilename" TEXT,
  ADD COLUMN IF NOT EXISTS "lastPrintPlateNumber" INTEGER DEFAULT 1,
  ADD COLUMN IF NOT EXISTS "lastPrintUseAms" BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS "lastPrintAmsMapping" INTEGER[] DEFAULT ARRAY[-1, -1, -1, -1, -1]::INTEGER[],
  ADD COLUMN IF NOT EXISTS "lastPrintAt" TIMESTAMPTZ(6);

COMMENT ON COLUMN "print-farm"."Printer"."lastPrintFilename"
  IS 'Nome del file dell''ultimo job (con estensione .gcode/.3mf, best-effort)';
COMMENT ON COLUMN "print-farm"."Printer"."lastPrintPlateNumber"
  IS 'Numero del plate dell''ultimo job (index)';
COMMENT ON COLUMN "print-farm"."Printer"."lastPrintUseAms"
  IS 'Se l''ultimo job usava AMS';
COMMENT ON COLUMN "print-farm"."Printer"."lastPrintAmsMapping"
  IS 'Mapping AMS dell''ultimo job (5 elementi, best-effort)';
COMMENT ON COLUMN "print-farm"."Printer"."lastPrintAt"
  IS 'Timestamp (server) dell''ultimo job avviato';

-- Backfill di sicurezza (per eventuali DB con colonne già presenti ma NULL)
UPDATE "print-farm"."Printer"
SET
  "lastPrintPlateNumber" = COALESCE("lastPrintPlateNumber", 1),
  "lastPrintUseAms" = COALESCE("lastPrintUseAms", true),
  "lastPrintAmsMapping" = COALESCE("lastPrintAmsMapping", ARRAY[-1, -1, -1, -1, -1]::INTEGER[])
WHERE "lastPrintFilename" IS NOT NULL;

