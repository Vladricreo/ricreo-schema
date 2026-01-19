-- Add BOM priority fields for product relations (Option B compatible).
-- Note: these are ordering fields for the Product BOM (not Item.specPriority).

ALTER TABLE inventory."ProductToPackage"
  ADD COLUMN IF NOT EXISTS "priority" integer NOT NULL DEFAULT 0;

ALTER TABLE inventory."ProductToComponent"
  ADD COLUMN IF NOT EXISTS "priority" integer NOT NULL DEFAULT 0;

ALTER TABLE inventory."ProductToUtility"
  ADD COLUMN IF NOT EXISTS "priority" integer NOT NULL DEFAULT 0;

ALTER TABLE inventory."ProductPartMaterial"
  ADD COLUMN IF NOT EXISTS "priority" integer NOT NULL DEFAULT 0;

-- Indexes to support stable ordering per product/part
CREATE INDEX IF NOT EXISTS "ProductToPackage_productId_priority_idx"
  ON inventory."ProductToPackage" ("productId", "priority");

CREATE INDEX IF NOT EXISTS "ProductToComponent_productId_priority_idx"
  ON inventory."ProductToComponent" ("productId", "priority");

CREATE INDEX IF NOT EXISTS "ProductToUtility_productId_priority_idx"
  ON inventory."ProductToUtility" ("productId", "priority");

CREATE INDEX IF NOT EXISTS "ProductPartMaterial_productPartId_priority_idx"
  ON inventory."ProductPartMaterial" ("productPartId", "priority");

