-- Camera riscaldata (decisione utente 2026-11-02, R-174).
-- 1. PrinterModel.hasHeatedChamber: il modello ha la camera riscaldata.
--    Precompilato per i modelli Bambu con riscaldatore camera (in farm: X2D,
--    le Cerbero). P1S e X1C restano false.
-- 2. FilamentProfile.requireHeatedChamberForPrint: l'articolo si stampa solo su
--    stampanti con camera riscaldata (es. Ddpe abs nero). Si attiva da
--    Impostazioni → Materiali; la migrazione non lo accende su nessun articolo.
--
-- Additiva e idempotente: ADD COLUMN IF NOT EXISTS con default false.

ALTER TABLE "print-farm"."PrinterModel"
  ADD COLUMN IF NOT EXISTS "hasHeatedChamber" BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN "print-farm"."PrinterModel"."hasHeatedChamber"
  IS 'True se il modello ha la camera riscaldata. Solo queste stampanti ricevono gli articoli con FilamentProfile.requireHeatedChamberForPrint (R-174).';

UPDATE "print-farm"."PrinterModel"
SET "hasHeatedChamber" = true
WHERE upper("name" || ' ' || "deviceModel") ~ '(^|[^A-Z0-9])(X2D|H2D|H2C|H2S|X1E)([^A-Z0-9]|$)';

ALTER TABLE "print-farm"."FilamentProfile"
  ADD COLUMN IF NOT EXISTS "requireHeatedChamberForPrint" BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN "print-farm"."FilamentProfile"."requireHeatedChamberForPrint"
  IS 'True se l''articolo si stampa solo su stampanti con camera riscaldata (PrinterModel.hasHeatedChamber). Scheduler, Gantt e piano bobine non lo propongono sulle altre; montaggio manuale con avviso (R-174).';
