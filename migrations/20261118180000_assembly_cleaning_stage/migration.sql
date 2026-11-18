-- R-276 (18/11/2026): fase «Pulizia» (CLEANING) prima dell'assemblaggio.
--
-- Alcuni prodotti, dopo la stampa, si puliscono (stress mark, sbavature) e si
-- scartano i pezzi non buoni prima di assemblarli. La pulizia avviene nella stessa
-- odetta: i pezzi restano parti separate, non diventano giacenza di una fase.
--
-- 1. AssemblyStageType.CLEANING: stage facoltativo del prodotto, sempre il primo.
-- 2. AssemblyOperationType.CLEANING: fase di manodopera a sé.
-- 3. AssemblyJournalKind.CLEAN: voce di diario della pulizia (annullabile).
-- 4. OdetteContent.cleanedQuantity: pezzi della riga già puliti (0..quantity).
--    Le parti restano nel magazzino parti fino al consumo in assemblaggio: copertura,
--    ristampe, completamento kit e lotti non cambiano.
--
-- Additiva: valori di enum nuovi (non usati in questa migrazione), colonna con
-- default 0, trigger che tiene cleanedQuantity entro quantity.
-- Il costo prodotto (v_assembly_labor_samples → v_product_labor_time_stats) somma
-- già tutte le sessioni dell'ordine, qualunque sia il tipo: nessuna vista da rifare.

ALTER TYPE "inventory"."AssemblyStageType" ADD VALUE IF NOT EXISTS 'CLEANING' BEFORE 'ASSEMBLED';
ALTER TYPE "inventory"."AssemblyOperationType" ADD VALUE IF NOT EXISTS 'CLEANING' BEFORE 'ASSEMBLY';
ALTER TYPE "inventory"."AssemblyJournalKind" ADD VALUE IF NOT EXISTS 'CLEAN';

ALTER TABLE "inventory"."OdetteContent"
  ADD COLUMN IF NOT EXISTS "cleanedQuantity" INTEGER NOT NULL DEFAULT 0;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'OdetteContent_cleanedQuantity_nonneg'
  ) THEN
    ALTER TABLE "inventory"."OdetteContent"
      ADD CONSTRAINT "OdetteContent_cleanedQuantity_nonneg"
      CHECK ("cleanedQuantity" >= 0);
  END IF;
END $$;

COMMENT ON COLUMN "inventory"."OdetteContent"."cleanedQuantity"
  IS 'R-276: pezzi della riga già puliti (fase Pulizia), da 0 a quantity. Il consumo in assemblaggio li toglie per primi.';

-- Tiene i puliti entro la quantità della riga. Copre i percorsi che riducono la
-- riga senza conoscere la pulizia (revert dello scarico Print Farm, rettifiche):
-- se la riga cala sotto i puliti, i puliti scendono con lei.
CREATE OR REPLACE FUNCTION inventory.odette_content_clamp_cleaned()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW."cleanedQuantity" IS NULL OR NEW."cleanedQuantity" < 0 THEN
    NEW."cleanedQuantity" := 0;
  END IF;
  IF NEW."cleanedQuantity" > GREATEST(COALESCE(NEW.quantity, 0), 0) THEN
    NEW."cleanedQuantity" := GREATEST(COALESCE(NEW.quantity, 0), 0);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_odette_content_clamp_cleaned ON "inventory"."OdetteContent";
CREATE TRIGGER trg_odette_content_clamp_cleaned
  BEFORE INSERT OR UPDATE OF quantity, "cleanedQuantity" ON "inventory"."OdetteContent"
  FOR EACH ROW
  EXECUTE FUNCTION inventory.odette_content_clamp_cleaned();
