-- Commissioni di vendita Shopify (regola provvisoria quando l'ordine non riporta
-- le fee Shopify Payments, es. PayPal o altri gateway).
-- Default: tariffa carte online EU del piano Basic (1,9% + 0,25 €), modificabile in Profitto.

-- AlterTable
ALTER TABLE "product"."ChannelSaleFeeSetting"
  ADD COLUMN IF NOT EXISTS "shopifyPercent" DECIMAL(5,2) NOT NULL DEFAULT 1.9,
  ADD COLUMN IF NOT EXISTS "shopifyFixedEur" DECIMAL(8,2) NOT NULL DEFAULT 0.25;
