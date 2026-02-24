-- Aggiunge campi per rilevazione incongruenza filamento sulla stampante.
-- Il backend WSS setta hasFilamentMismatch=true quando il materiale/colore
-- riportato dal firmware non corrisponde alla spool tracciata nel DB.

ALTER TABLE "print-farm"."Printer"
  ADD COLUMN IF NOT EXISTS "hasFilamentMismatch" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "filamentMismatchDetectedAt" TIMESTAMPTZ(6),
  ADD COLUMN IF NOT EXISTS "filamentMismatchDetails" JSONB;
