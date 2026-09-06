-- Profilo di slicing del file 3MF (single/dual nozzle) + intercambiabilita' nozzle del modello.
-- Cfr. docs/multi-nozzle-multi-ams-support.md §13.
--
-- Additiva e idempotente: solo ADD COLUMN con IF NOT EXISTS. Nessun consumer legacy viene rotto
-- (tutti i campi nuovi sono nullable o hanno default).

-- ─── 1) ProjectThreeMFFile: profilo di slicing ─────────────────────────────
ALTER TABLE "print-farm"."ProjectThreeMFFile"
  ADD COLUMN IF NOT EXISTS "nozzleMode"                TEXT,
  ADD COLUMN IF NOT EXISTS "pinnedExtruder"            INTEGER,
  ADD COLUMN IF NOT EXISTS "sliceMapMode"              TEXT,
  ADD COLUMN IF NOT EXISTS "fileExpectsFts"            BOOLEAN,
  ADD COLUMN IF NOT EXISTS "extruderTypes"             INTEGER[]     NOT NULL DEFAULT ARRAY[]::INTEGER[],
  ADD COLUMN IF NOT EXISTS "nozzleDiametersByExtruder" DECIMAL(4,2)[] NOT NULL DEFAULT ARRAY[]::DECIMAL(4,2)[];

COMMENT ON COLUMN "print-farm"."ProjectThreeMFFile"."nozzleMode"
  IS 'Classificazione slicing: SINGLE (un extruder) | DUAL (>=2 extruder distinti). Null per file legacy.';
COMMENT ON COLUMN "print-farm"."ProjectThreeMFFile"."pinnedExtruder"
  IS 'Extruder a cui e'' pinnato un file SINGLE (es. tutto su left=1). Null = ext0/legacy.';
COMMENT ON COLUMN "print-farm"."ProjectThreeMFFile"."sliceMapMode"
  IS 'Modalita'' mappa filamenti del file: MANUAL | AUTO | DYNAMIC.';
COMMENT ON COLUMN "print-farm"."ProjectThreeMFFile"."fileExpectsFts"
  IS 'True se il file e'' stato affettato assumendo il Filament Track Switch (has_filament_switcher).';

-- ─── 2) PrinterModel: nozzle intercambiabili ───────────────────────────────
ALTER TABLE "print-farm"."PrinterModel"
  ADD COLUMN IF NOT EXISTS "extruderAssignmentSwappable" BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN "print-farm"."PrinterModel"."extruderAssignmentSwappable"
  IS 'True se i nozzle sono equivalenti (es. H2D direct drive): mappa filamento->extruder permutabile. False (X2D): rigida.';

-- Backfill best-effort: H2D / H2D Pro hanno nozzle equivalenti (entrambi direct drive).
UPDATE "print-farm"."PrinterModel"
SET "extruderAssignmentSwappable" = true
WHERE "name" ILIKE '%H2D%' OR "deviceModel" ILIKE '%H2D%';
