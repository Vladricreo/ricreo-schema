-- Allow BOM rows per specific Item (variant) even when grouped under same ItemSpec.
-- This fixes the case "1 part with 2 materials under same spec" where weights get collapsed.

ALTER TABLE "inventory"."ProductPartMaterial"
  ADD COLUMN IF NOT EXISTS "materialItemId" uuid NULL;

-- Backfill: if there is a 1:1 mapping (ItemSpec.id == Item.id) use it.
-- Otherwise we keep NULL (old rows keep working; new writes will always set materialItemId).
UPDATE "inventory"."ProductPartMaterial" ppm
SET "materialItemId" = ppm."materialSpecId"
WHERE ppm."materialItemId" IS NULL
  AND EXISTS (
    SELECT 1
    FROM "inventory"."Item" i
    WHERE i."id" = ppm."materialSpecId"
  );

-- FK to Item (variant)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint c
    WHERE c.conname = 'ProductPartMaterial_materialItemId_fkey'
      AND c.conrelid = to_regclass('inventory."ProductPartMaterial"')
  ) THEN
    ALTER TABLE "inventory"."ProductPartMaterial"
      ADD CONSTRAINT "ProductPartMaterial_materialItemId_fkey"
      FOREIGN KEY ("materialItemId") REFERENCES "inventory"."Item"("id")
      ON DELETE RESTRICT
      ON UPDATE CASCADE;
  END IF;
END $$;

-- Drop old uniqueness by spec (it prevents multiple materials under same spec)
-- In Postgres this is a UNIQUE CONSTRAINT (backed by an index), so drop the constraint.
ALTER TABLE "inventory"."ProductPartMaterial"
  DROP CONSTRAINT IF EXISTS "ProductPartMaterial_productPartId_materialSpecId_key";

-- Enforce uniqueness per Item (variant). Multiple NULLs are allowed in Postgres.
CREATE UNIQUE INDEX IF NOT EXISTS "ProductPartMaterial_productPartId_materialItemId_key"
  ON "inventory"."ProductPartMaterial" ("productPartId", "materialItemId");

-- Helpful index for queries
CREATE INDEX IF NOT EXISTS "ProductPartMaterial_materialItemId_idx"
  ON "inventory"."ProductPartMaterial" ("materialItemId");

