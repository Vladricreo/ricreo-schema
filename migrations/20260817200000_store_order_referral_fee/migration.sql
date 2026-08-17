-- Commissione di vendita reale da Finances (oltre alla fee FBA).
-- Solo schema product.

ALTER TABLE "product"."StoreOrderFee"
    ADD COLUMN IF NOT EXISTS "referralFee" DECIMAL(12,4) NOT NULL DEFAULT 0;
