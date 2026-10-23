-- Default di pubblicazione Shopify nel wizard Crossplatform.
-- Solo colonne nuove con default: nessuna riga esistente cambia significato.

-- AlterTable
ALTER TABLE "product"."CrossplatformPublishDefaults"
  ADD COLUMN IF NOT EXISTS "shopifyVendor" TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS "shopifyProductType" TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS "shopifyStatus" TEXT NOT NULL DEFAULT 'ACTIVE',
  ADD COLUMN IF NOT EXISTS "shopifyPublishOnlineStore" BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS "shopifyTags" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];
