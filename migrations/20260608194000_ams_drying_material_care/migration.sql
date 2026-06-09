-- Regole di cura filamento per asciugatura AMS.
-- Additiva e idempotente: non cambia il comportamento esistente finche' i flag restano false.

ALTER TABLE "print-farm"."FilamentProfile"
  ADD COLUMN IF NOT EXISTS "warnDryOpenedSpoolBeforePrint" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "requireHeatedAmsForPrint" BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN "print-farm"."FilamentProfile"."warnDryOpenedSpoolBeforePrint"
  IS 'True: se una bobina aperta usa questo materiale, mostra un warning asciugatura prima della stampa.';

COMMENT ON COLUMN "print-farm"."FilamentProfile"."requireHeatedAmsForPrint"
  IS 'True: il materiale deve essere stampato da AMS riscaldata (AMS HT o AMS 2 Pro).';

ALTER TABLE "print-farm"."FilamentSpool"
  ADD COLUMN IF NOT EXISTS "lastDriedAt" TIMESTAMPTZ;

COMMENT ON COLUMN "print-farm"."FilamentSpool"."lastDriedAt"
  IS 'Timestamp ultima asciugatura confermata o osservata per la bobina.';
