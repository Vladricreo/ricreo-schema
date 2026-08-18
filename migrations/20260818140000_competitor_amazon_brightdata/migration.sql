-- Catalogo Amazon concorrenti: galleria foto, unità mensili Bright Data,
-- stato sync sul canale. Solo schema product.

ALTER TABLE "product"."CompetitorChannel"
    ADD COLUMN IF NOT EXISTS "lastSyncMeta" JSONB;

ALTER TABLE "product"."CompetitorProduct"
    ADD COLUMN IF NOT EXISTS "imageUrls" JSONB,
    ADD COLUMN IF NOT EXISTS "boughtPastMonth" INTEGER,
    ADD COLUMN IF NOT EXISTS "searchSold" INTEGER;

CREATE TABLE IF NOT EXISTS "product"."CompetitorMonthlySoldSnapshot" (
    "id" TEXT NOT NULL,
    "productId" TEXT NOT NULL,
    "countryCode" TEXT NOT NULL,
    "marketplaceKey" TEXT NOT NULL,
    "capturedAt" DATE NOT NULL,
    "boughtPastMonth" INTEGER,
    "sold" INTEGER,
    "source" TEXT NOT NULL DEFAULT 'BRIGHTDATA',
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "CompetitorMonthlySoldSnapshot_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "CompetitorMonthlySoldSnapshot_day_key"
    ON "product"."CompetitorMonthlySoldSnapshot"("productId", "marketplaceKey", "capturedAt");
CREATE INDEX IF NOT EXISTS "CompetitorMonthlySoldSnapshot_product_date"
    ON "product"."CompetitorMonthlySoldSnapshot"("productId", "capturedAt");

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'CompetitorMonthlySoldSnapshot_productId_fkey'
    ) THEN
        ALTER TABLE "product"."CompetitorMonthlySoldSnapshot"
            ADD CONSTRAINT "CompetitorMonthlySoldSnapshot_productId_fkey"
            FOREIGN KEY ("productId") REFERENCES "product"."CompetitorProduct"("id")
            ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
END $$;
