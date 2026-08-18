-- Foto listing per matching: copia storage + dHash locale (niente Jina).
-- Solo schema product.

ALTER TABLE "product"."ListingMatchFeature"
    ADD COLUMN IF NOT EXISTS "storedImagePath" TEXT,
    ADD COLUMN IF NOT EXISTS "imageHash" TEXT;

CREATE INDEX IF NOT EXISTS "ListingMatchFeature_imageHash_idx"
    ON "product"."ListingMatchFeature"("imageHash");
