-- Scorporo Digital Services Fee dagli eventi Finances (resta anche in referralFee).
-- Solo schema product.

ALTER TABLE "product"."StoreOrderFee"
    ADD COLUMN IF NOT EXISTS "digitalServicesFee" DECIMAL(12,4) NOT NULL DEFAULT 0;
