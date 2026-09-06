-- Riscaldamento AMS mantenuto durante la stampa.
--
-- Distinto dall'asciugatura: non produce una sessione tracciata e non rende la
-- bobina "asciutta". E' una temperatura di mantenimento che il backend avvia
-- contestualmente allo start sull'unita' che alimenta la stampa
-- (`close_power_conflict = true`).

ALTER TABLE "print-farm"."FilamentProfile"
  ADD COLUMN IF NOT EXISTS "keepAmsHeatedDuringPrint" BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE "print-farm"."FilamentProfile"
  ADD COLUMN IF NOT EXISTS "amsHeatDuringPrintTempC" INTEGER;

-- Il mantenimento richiede una temperatura entro i limiti hardware (AMS HT 85 °C).
ALTER TABLE "print-farm"."FilamentProfile"
  DROP CONSTRAINT IF EXISTS "FilamentProfile_amsHeatDuringPrintTempC_check";
ALTER TABLE "print-farm"."FilamentProfile"
  ADD CONSTRAINT "FilamentProfile_amsHeatDuringPrintTempC_check"
  CHECK (
    "amsHeatDuringPrintTempC" IS NULL
    OR ("amsHeatDuringPrintTempC" > 0 AND "amsHeatDuringPrintTempC" <= 85)
  );

-- Senza temperatura il mantenimento non e' eseguibile: il backend salterebbe
-- l'unita', quindi il flag non deve poter restare attivo "a vuoto".
ALTER TABLE "print-farm"."FilamentProfile"
  DROP CONSTRAINT IF EXISTS "FilamentProfile_keepAmsHeatedDuringPrint_check";
ALTER TABLE "print-farm"."FilamentProfile"
  ADD CONSTRAINT "FilamentProfile_keepAmsHeatedDuringPrint_check"
  CHECK (
    "keepAmsHeatedDuringPrint" = false
    OR "amsHeatDuringPrintTempC" IS NOT NULL
  );
