-- Multi-nozzle slicing per SliceJob (Bambu H2D / X2D dual-nozzle, sperimentale).
-- Riferimento: docs/multi-nozzle-multi-ams-support.md + OrcaSlicer `filament_map`/`filament_map_mode`.
--
-- Aggiunge:
--   • "SliceJob"."filamentProfile2Id" (FK opzionale a SlicerProfile = filamento del 2° nozzle)
--   • "SliceJob"."filamentMapMode"    (TEXT = `filament_map_mode` Orca, es. "Manual")
--
-- Idempotente: ADD COLUMN IF NOT EXISTS + guard su pg_constraint per la FK + CREATE INDEX IF NOT EXISTS.
-- Additiva: nessun consumer esistente viene rotto (le colonne sono nullable).

-- ─── 1) Colonne nuove su SliceJob ───────────────────────────────────────────
ALTER TABLE "print-farm"."SliceJob"
  ADD COLUMN IF NOT EXISTS "filamentProfile2Id" UUID,
  ADD COLUMN IF NOT EXISTS "filamentMapMode" TEXT;

COMMENT ON COLUMN "print-farm"."SliceJob"."filamentProfile2Id"
  IS 'Profilo FILAMENT del secondo nozzle (solo stampanti dual-nozzle H2D/X2D). Orca filament_map=2.';
COMMENT ON COLUMN "print-farm"."SliceJob"."filamentMapMode"
  IS 'Modalità raggruppamento filamenti Orca (filament_map_mode), es. "Manual"/"Auto For Flush"/"Auto For Quality".';

-- ─── 2) FK SliceJob.filamentProfile2Id -> SlicerProfile.id (SET NULL) ────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'SliceJob_filamentProfile2Id_fkey'
  ) THEN
    ALTER TABLE "print-farm"."SliceJob"
      ADD CONSTRAINT "SliceJob_filamentProfile2Id_fkey"
      FOREIGN KEY ("filamentProfile2Id") REFERENCES "print-farm"."SlicerProfile"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;

-- ─── 3) Indice ──────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS "SliceJob_filamentProfile2Id_idx"
  ON "print-farm"."SliceJob"("filamentProfile2Id");
