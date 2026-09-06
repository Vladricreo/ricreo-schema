-- Costi settlement/Finances oltre referral e FBA: storno, rimborso, altre ItemFees.
-- Solo schema product.

ALTER TABLE "product"."StoreOrderFee"
    ADD COLUMN IF NOT EXISTS "shippingChargeback" DECIMAL(12,4) NOT NULL DEFAULT 0;

ALTER TABLE "product"."StoreOrderFee"
    ADD COLUMN IF NOT EXISTS "refundCommission" DECIMAL(12,4) NOT NULL DEFAULT 0;

ALTER TABLE "product"."StoreOrderFee"
    ADD COLUMN IF NOT EXISTS "otherFee" DECIMAL(12,4) NOT NULL DEFAULT 0;
