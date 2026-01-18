-- =============================================================================
-- ItemSpec (Option B) - hard migration (initial 1:1 mapping)
-- =============================================================================
-- Obiettivo:
-- - introdurre `inventory."ItemSpec"` come target BOM
-- - migrare le join (ProductTo*) da itemId -> itemSpecId
-- - migrare ProductPartMaterial da materialId -> materialSpecId
-- - aggiungere `Movement.itemSpecId` per audit/fallback
--
-- Strategia (1:1 iniziale, senza funzioni UUID):
-- - usiamo `ItemSpec.id = Item.id` così:
--   - non servono generatori UUID
--   - la migrazione è deterministica e veloce
--
-- Nota: dopo la migrazione potrai raggruppare più Item sotto la stessa ItemSpec
-- aggiornando `Item.itemSpecId` + `Item.specPriority`.

-- ---------------------------------------------------------------------------
-- 1) Nuove tabelle
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS inventory."ItemSpec" (
  "id" uuid PRIMARY KEY,
  "name" text NOT NULL,
  "type" inventory."ItemType" NOT NULL,
  "packagingTypeId" uuid NULL,
  "notes" text NULL,
  "properties" jsonb NULL,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "ItemSpec_type_idx" ON inventory."ItemSpec" ("type");
CREATE INDEX IF NOT EXISTS "ItemSpec_name_idx" ON inventory."ItemSpec" ("name");
CREATE INDEX IF NOT EXISTS "ItemSpec_packagingTypeId_idx" ON inventory."ItemSpec" ("packagingTypeId");

CREATE TABLE IF NOT EXISTS inventory."ItemSpecOverride" (
  "id" uuid PRIMARY KEY,
  "specId" uuid NOT NULL UNIQUE,
  "itemId" uuid NOT NULL,
  "isActive" boolean NOT NULL DEFAULT true,
  "startsAt" timestamptz NOT NULL DEFAULT now(),
  "endsAt" timestamptz NULL,
  "reason" text NOT NULL,
  "approvedByUserId" integer NULL,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "ItemSpecOverride_itemId_idx" ON inventory."ItemSpecOverride" ("itemId");
CREATE INDEX IF NOT EXISTS "ItemSpecOverride_isActive_idx" ON inventory."ItemSpecOverride" ("isActive");
CREATE INDEX IF NOT EXISTS "ItemSpecOverride_approvedByUserId_idx" ON inventory."ItemSpecOverride" ("approvedByUserId");

ALTER TABLE inventory."ItemSpec"
  ADD CONSTRAINT "ItemSpec_packagingTypeId_fkey"
  FOREIGN KEY ("packagingTypeId") REFERENCES inventory."PackagingType"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE inventory."ItemSpecOverride"
  ADD CONSTRAINT "ItemSpecOverride_specId_fkey"
  FOREIGN KEY ("specId") REFERENCES inventory."ItemSpec"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE inventory."ItemSpecOverride"
  ADD CONSTRAINT "ItemSpecOverride_itemId_fkey"
  FOREIGN KEY ("itemId") REFERENCES inventory."Item"("id")
  ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE inventory."ItemSpecOverride"
  ADD CONSTRAINT "ItemSpecOverride_approvedByUserId_fkey"
  FOREIGN KEY ("approvedByUserId") REFERENCES public."User"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

-- ---------------------------------------------------------------------------
-- 2) Item: nuove colonne + seed ItemSpec (1:1)
-- ---------------------------------------------------------------------------

ALTER TABLE inventory."Item" ADD COLUMN IF NOT EXISTS "itemSpecId" uuid NULL;
ALTER TABLE inventory."Item" ADD COLUMN IF NOT EXISTS "specPriority" integer NOT NULL DEFAULT 0;

-- Crea la spec 1:1 se non esiste già
INSERT INTO inventory."ItemSpec" ("id", "name", "type", "packagingTypeId", "createdAt", "updatedAt")
SELECT i."id", i."name", i."type", i."packagingTypeId", now(), now()
FROM inventory."Item" i
WHERE NOT EXISTS (
  SELECT 1 FROM inventory."ItemSpec" s WHERE s."id" = i."id"
);

-- Backfill: ogni Item punta alla propria spec (id = item.id)
UPDATE inventory."Item"
SET "itemSpecId" = "id"
WHERE "itemSpecId" IS NULL;

ALTER TABLE inventory."Item"
  ADD CONSTRAINT "Item_itemSpecId_fkey"
  FOREIGN KEY ("itemSpecId") REFERENCES inventory."ItemSpec"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

CREATE INDEX IF NOT EXISTS "Item_itemSpecId_specPriority_idx"
  ON inventory."Item" ("itemSpecId", "specPriority");

-- ---------------------------------------------------------------------------
-- 3) Movement: audit itemSpecId
-- ---------------------------------------------------------------------------

ALTER TABLE inventory."Movement" ADD COLUMN IF NOT EXISTS "itemSpecId" uuid NULL;

UPDATE inventory."Movement"
SET "itemSpecId" = "itemId"
WHERE "itemSpecId" IS NULL
  AND "itemId" IS NOT NULL;

ALTER TABLE inventory."Movement"
  ADD CONSTRAINT "Movement_itemSpecId_fkey"
  FOREIGN KEY ("itemSpecId") REFERENCES inventory."ItemSpec"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

CREATE INDEX IF NOT EXISTS "Movement_itemSpecId_idx"
  ON inventory."Movement" ("itemSpecId");

-- ---------------------------------------------------------------------------
-- 4) BOM joins: ProductTo* (itemId -> itemSpecId)
-- ---------------------------------------------------------------------------

-- ProductToPackage
ALTER TABLE inventory."ProductToPackage" ADD COLUMN IF NOT EXISTS "itemSpecId" uuid NULL;
UPDATE inventory."ProductToPackage" SET "itemSpecId" = "itemId" WHERE "itemSpecId" IS NULL;
ALTER TABLE inventory."ProductToPackage" DROP CONSTRAINT IF EXISTS "ProductToPackage_itemId_fkey";
ALTER TABLE inventory."ProductToPackage"
  ADD CONSTRAINT "ProductToPackage_itemSpecId_fkey"
  FOREIGN KEY ("itemSpecId") REFERENCES inventory."ItemSpec"("id")
  ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE inventory."ProductToPackage" DROP CONSTRAINT IF EXISTS "ProductToPackage_pkey";
ALTER TABLE inventory."ProductToPackage" DROP COLUMN IF EXISTS "itemId";
ALTER TABLE inventory."ProductToPackage" ADD PRIMARY KEY ("productId", "itemSpecId");
CREATE INDEX IF NOT EXISTS "ProductToPackage_itemSpecId_idx" ON inventory."ProductToPackage" ("itemSpecId");

-- ProductToComponent
ALTER TABLE inventory."ProductToComponent" ADD COLUMN IF NOT EXISTS "itemSpecId" uuid NULL;
UPDATE inventory."ProductToComponent" SET "itemSpecId" = "itemId" WHERE "itemSpecId" IS NULL;
ALTER TABLE inventory."ProductToComponent" DROP CONSTRAINT IF EXISTS "ProductToComponent_itemId_fkey";
ALTER TABLE inventory."ProductToComponent"
  ADD CONSTRAINT "ProductToComponent_itemSpecId_fkey"
  FOREIGN KEY ("itemSpecId") REFERENCES inventory."ItemSpec"("id")
  ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE inventory."ProductToComponent" DROP CONSTRAINT IF EXISTS "ProductToComponent_pkey";
ALTER TABLE inventory."ProductToComponent" DROP COLUMN IF EXISTS "itemId";
ALTER TABLE inventory."ProductToComponent" ADD PRIMARY KEY ("productId", "itemSpecId");
CREATE INDEX IF NOT EXISTS "ProductToComponent_itemSpecId_idx" ON inventory."ProductToComponent" ("itemSpecId");

-- ProductToTool
ALTER TABLE inventory."ProductToTool" ADD COLUMN IF NOT EXISTS "itemSpecId" uuid NULL;
UPDATE inventory."ProductToTool" SET "itemSpecId" = "itemId" WHERE "itemSpecId" IS NULL;
ALTER TABLE inventory."ProductToTool" DROP CONSTRAINT IF EXISTS "ProductToTool_itemId_fkey";
ALTER TABLE inventory."ProductToTool"
  ADD CONSTRAINT "ProductToTool_itemSpecId_fkey"
  FOREIGN KEY ("itemSpecId") REFERENCES inventory."ItemSpec"("id")
  ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE inventory."ProductToTool" DROP CONSTRAINT IF EXISTS "ProductToTool_pkey";
ALTER TABLE inventory."ProductToTool" DROP COLUMN IF EXISTS "itemId";
ALTER TABLE inventory."ProductToTool" ADD PRIMARY KEY ("productId", "itemSpecId");
CREATE INDEX IF NOT EXISTS "ProductToTool_itemSpecId_idx" ON inventory."ProductToTool" ("itemSpecId");

-- ProductToUtility
ALTER TABLE inventory."ProductToUtility" ADD COLUMN IF NOT EXISTS "itemSpecId" uuid NULL;
UPDATE inventory."ProductToUtility" SET "itemSpecId" = "itemId" WHERE "itemSpecId" IS NULL;
ALTER TABLE inventory."ProductToUtility" DROP CONSTRAINT IF EXISTS "ProductToUtility_itemId_fkey";
ALTER TABLE inventory."ProductToUtility"
  ADD CONSTRAINT "ProductToUtility_itemSpecId_fkey"
  FOREIGN KEY ("itemSpecId") REFERENCES inventory."ItemSpec"("id")
  ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE inventory."ProductToUtility" DROP CONSTRAINT IF EXISTS "ProductToUtility_pkey";
ALTER TABLE inventory."ProductToUtility" DROP COLUMN IF EXISTS "itemId";
ALTER TABLE inventory."ProductToUtility" ADD PRIMARY KEY ("productId", "itemSpecId");
CREATE INDEX IF NOT EXISTS "ProductToUtility_itemSpecId_idx" ON inventory."ProductToUtility" ("itemSpecId");

-- ---------------------------------------------------------------------------
-- 5) ProductPartMaterial: materialId -> materialSpecId
-- ---------------------------------------------------------------------------

ALTER TABLE inventory."ProductPartMaterial" ADD COLUMN IF NOT EXISTS "materialSpecId" uuid NULL;
UPDATE inventory."ProductPartMaterial" SET "materialSpecId" = "materialId" WHERE "materialSpecId" IS NULL;

ALTER TABLE inventory."ProductPartMaterial" DROP CONSTRAINT IF EXISTS "ProductPartMaterial_materialId_fkey";
ALTER TABLE inventory."ProductPartMaterial"
  ADD CONSTRAINT "ProductPartMaterial_materialSpecId_fkey"
  FOREIGN KEY ("materialSpecId") REFERENCES inventory."ItemSpec"("id")
  ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE inventory."ProductPartMaterial" DROP CONSTRAINT IF EXISTS "ProductPartMaterial_productPartId_materialId_key";
ALTER TABLE inventory."ProductPartMaterial" DROP COLUMN IF EXISTS "materialId";
ALTER TABLE inventory."ProductPartMaterial"
  ADD CONSTRAINT "ProductPartMaterial_productPartId_materialSpecId_key"
  UNIQUE ("productPartId", "materialSpecId");

CREATE INDEX IF NOT EXISTS "ProductPartMaterial_materialSpecId_idx"
  ON inventory."ProductPartMaterial" ("materialSpecId");

