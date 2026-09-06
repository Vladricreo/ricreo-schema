-- Metadati catalogo qualità: data pubblicazione, categorie Amazon e
-- collegamento a inventory.Product (ASIN / EAN / SKU). Job extra SKU.

ALTER TABLE "product"."StoreListingContentSnapshot"
  ADD COLUMN IF NOT EXISTS "publishedAt" DATE,
  ADD COLUMN IF NOT EXISTS "amazonCategory" TEXT,
  ADD COLUMN IF NOT EXISTS "amazonCategoryKey" TEXT,
  ADD COLUMN IF NOT EXISTS "amazonSubcategory" TEXT,
  ADD COLUMN IF NOT EXISTS "amazonSubcategoryKey" TEXT,
  ADD COLUMN IF NOT EXISTS "ean" TEXT,
  ADD COLUMN IF NOT EXISTS "inventoryProductId" UUID,
  ADD COLUMN IF NOT EXISTS "inventoryProductName" TEXT;

CREATE INDEX IF NOT EXISTS "StoreListingContent_inventory_product"
  ON "product"."StoreListingContentSnapshot" ("inventoryProductId");

ALTER TABLE "product"."StoreQualityDailyJob"
  ADD COLUMN IF NOT EXISTS "nextExtraOffset" INTEGER NOT NULL DEFAULT 0;
