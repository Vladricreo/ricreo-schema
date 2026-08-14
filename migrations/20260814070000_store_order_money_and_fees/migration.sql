-- IVA, spedizione e sconti dagli all-orders; stime commissioni FBA Fee Preview.
-- Solo schema product.

ALTER TABLE "product"."StoreOrderLine"
    ADD COLUMN "itemTax" DECIMAL(12,2),
    ADD COLUMN "shippingPrice" DECIMAL(12,2),
    ADD COLUMN "shippingTax" DECIMAL(12,2),
    ADD COLUMN "itemPromotionDiscount" DECIMAL(12,2),
    ADD COLUMN "shipPromotionDiscount" DECIMAL(12,2);

CREATE TABLE "product"."StoreSkuFeeEstimate" (
    "id" TEXT NOT NULL,
    "channel" "product"."StoreChannel" NOT NULL,
    "storeKey" TEXT NOT NULL,
    "sku" TEXT NOT NULL,
    "currency" TEXT,
    "referralFeePerUnit" DECIMAL(12,4),
    "fbaFeeDomestic" DECIMAL(12,4),
    "fbaFeeByCountry" JSONB,
    "estimatedFeeTotal" DECIMAL(12,4),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "StoreSkuFeeEstimate_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "StoreSkuFeeEstimate_channel_storeKey_sku_key"
    ON "product"."StoreSkuFeeEstimate"("channel", "storeKey", "sku");
CREATE INDEX "StoreSkuFeeEstimate_sku_idx"
    ON "product"."StoreSkuFeeEstimate"("sku");
