-- Ricambi: stato "usato/rigenerato" + nota generale, e composizione multiparte.
--
-- Feature:
--  1) Item.isUsed / Item.note: marcare un ricambio come usato/rigenerato e annotarlo.
--  2) SparePartComponent: un ricambio "padre" (es. "Hotend completo") composto da
--     sotto-ricambi reali con stock proprio (ventolina, termistore, hotend).
--
-- Additiva e idempotente: ADD COLUMN IF NOT EXISTS + CREATE TABLE/INDEX IF NOT EXISTS
-- e constraint guardate da DO block (nessun consumer esistente viene rotto).

ALTER TABLE "inventory"."Item"
  ADD COLUMN IF NOT EXISTS "isUsed" BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE "inventory"."Item"
  ADD COLUMN IF NOT EXISTS "note" TEXT;

COMMENT ON COLUMN "inventory"."Item"."isUsed"
  IS 'Ricambio usato/rigenerato (rilevante per SPARE_PART). False = nuovo/di scorta.';
COMMENT ON COLUMN "inventory"."Item"."note"
  IS 'Nota generale sul ricambio (provenienza, condizione, avvertenze).';

-- Tabella composizione ricambi multiparte
CREATE TABLE IF NOT EXISTS "inventory"."SparePartComponent" (
  "id"        UUID NOT NULL DEFAULT gen_random_uuid(),
  "parentId"  UUID NOT NULL,
  "childId"   UUID NOT NULL,
  "quantity"  INTEGER NOT NULL DEFAULT 1,
  "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT now(),
  CONSTRAINT "SparePartComponent_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "SparePartComponent_parentId_childId_key"
  ON "inventory"."SparePartComponent" ("parentId", "childId");
CREATE INDEX IF NOT EXISTS "SparePartComponent_parentId_idx"
  ON "inventory"."SparePartComponent" ("parentId");
CREATE INDEX IF NOT EXISTS "SparePartComponent_childId_idx"
  ON "inventory"."SparePartComponent" ("childId");

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'SparePartComponent_parentId_fkey'
  ) THEN
    ALTER TABLE "inventory"."SparePartComponent"
      ADD CONSTRAINT "SparePartComponent_parentId_fkey"
      FOREIGN KEY ("parentId") REFERENCES "inventory"."Item"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'SparePartComponent_childId_fkey'
  ) THEN
    ALTER TABLE "inventory"."SparePartComponent"
      ADD CONSTRAINT "SparePartComponent_childId_fkey"
      FOREIGN KEY ("childId") REFERENCES "inventory"."Item"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END
$$;
