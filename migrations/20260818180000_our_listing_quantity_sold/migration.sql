-- Persist eBay lifetime QuantitySold on our listing match snapshot.
ALTER TABLE "product"."OurListingMatchSource"
ADD COLUMN IF NOT EXISTS "quantitySold" INTEGER;
