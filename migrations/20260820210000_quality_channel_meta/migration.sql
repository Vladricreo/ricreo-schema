-- Qualità multi-canale: metadati listing (tag/specifics) e sentiment eBay.

ALTER TABLE "product"."StoreListingContentSnapshot"
  ADD COLUMN IF NOT EXISTS "qualityMeta" JSONB;

ALTER TABLE "product"."StoreCustomerReview"
  ADD COLUMN IF NOT EXISTS "sentiment" TEXT;

COMMENT ON COLUMN "product"."StoreListingContentSnapshot"."asin" IS
  'Id listing del marketplace: ASIN Amazon, ItemID eBay, listing_id Etsy, goodsId Temu.';

COMMENT ON COLUMN "product"."StoreReviewSummary"."asin" IS
  'Id listing del marketplace: ASIN Amazon, ItemID eBay, listing_id Etsy, goodsId Temu.';

COMMENT ON COLUMN "product"."StoreCustomerReview"."asin" IS
  'Id listing del marketplace: ASIN Amazon, ItemID eBay, listing_id Etsy, goodsId Temu.';
