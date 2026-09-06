-- Percorso stampa PET-CF-like: bobina tracciata/asciugata in AMS HT,
-- carico e stampa dalla spool esterna del nozzle del file (vt_tray).
-- Distinto da requireAmsHtForPrint (alimentazione attraverso gli ingranaggi HT).

ALTER TABLE "print-farm"."FilamentProfile"
  ADD COLUMN IF NOT EXISTS "trackOnAmsHtPrintFromExternal" BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN "print-farm"."FilamentProfile"."trackOnAmsHtPrintFromExternal" IS
  'Traccia in AMS HT, stampa/carico da spool esterna del nozzle del file.';

-- I due percorsi HT sono mutuamente esclusivi.
ALTER TABLE "print-farm"."FilamentProfile"
  DROP CONSTRAINT IF EXISTS "FilamentProfile_ht_print_path_exclusive";
ALTER TABLE "print-farm"."FilamentProfile"
  ADD CONSTRAINT "FilamentProfile_ht_print_path_exclusive"
  CHECK (
    NOT ("requireAmsHtForPrint" = true AND "trackOnAmsHtPrintFromExternal" = true)
  );
