-- ============================================================================
-- F6 fase 1 — ProjectFileMaterial.materialSpecId (audit 2026-09-03:
-- PIANO-AZIONE ondata 6; F6-RECON gap #1).
--
-- Cosa cambia:
--   * `ProjectFileMaterial.materialSpecId` (UUID, NULL): spec/famiglia logica
--     del materiale del file (FK verso inventory."ItemSpec"). Sara' il DEFAULT
--     di matching F6; `materialId` (brand/variant) RESTA e diventa
--     preferenza/vincolo forte — non viene droppato (regola skeptic, REPORT §4).
--
-- La colonna e' NULL di default: il codice in produzione (vecchio) continua a
-- funzionare invariato e nessun dato esistente viene riscritto dalla
-- migrazione. Il backfill (deterministico da Item.itemSpecId) e' nello script
-- client/scripts/f6-backfill-file-material-spec.ts.
--
-- Tutto additivo e idempotente (IF NOT EXISTS / guardia pg_constraint).
--
-- Applicabile anche via psql / Supabase SQL editor. Se lo fai fuori da Prisma:
--   bunx prisma migrate resolve --applied 20260904020000_project_file_material_spec
-- ============================================================================

-- Colonna nullable: safe per il codice vecchio ancora in produzione.
ALTER TABLE "print-farm"."ProjectFileMaterial"
  ADD COLUMN IF NOT EXISTS "materialSpecId" UUID;

-- FK cross-schema verso inventory."ItemSpec" (ON DELETE SET NULL: se la spec
-- sparisce, la riga file-materiale resta e punta solo al brand `materialId`).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'ProjectFileMaterial_materialSpecId_fkey'
      AND conrelid = '"print-farm"."ProjectFileMaterial"'::regclass
  ) THEN
    ALTER TABLE "print-farm"."ProjectFileMaterial"
      ADD CONSTRAINT "ProjectFileMaterial_materialSpecId_fkey"
      FOREIGN KEY ("materialSpecId") REFERENCES "inventory"."ItemSpec"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;

-- Lookup per spec nel matching scheduler F6 (pool byItemSpec) e nel backfill.
CREATE INDEX IF NOT EXISTS "ProjectFileMaterial_materialSpecId_idx"
  ON "print-farm"."ProjectFileMaterial"("materialSpecId");
