-- Stato corrente FBA/Prime sull'offerta Amazon e storico giornaliero.
-- Solo schema product.

ALTER TABLE "product"."CompetitorListingOffer"
    ADD COLUMN IF NOT EXISTS "isFba" BOOLEAN,
    ADD COLUMN IF NOT EXISTS "isPrime" BOOLEAN;

CREATE TABLE IF NOT EXISTS "product"."CompetitorFulfillmentSnapshot" (
    "id" TEXT NOT NULL,
    "offerId" TEXT NOT NULL,
    "productId" TEXT NOT NULL,
    "countryCode" TEXT NOT NULL,
    "marketplaceKey" TEXT NOT NULL,
    "capturedAt" DATE NOT NULL,
    "isFba" BOOLEAN,
    "isPrime" BOOLEAN,
    "source" TEXT NOT NULL DEFAULT 'SP_API',
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "CompetitorFulfillmentSnapshot_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "CompetitorFulfillmentSnapshot_day_key"
    ON "product"."CompetitorFulfillmentSnapshot"("offerId", "capturedAt");
CREATE INDEX IF NOT EXISTS "CompetitorFulfillmentSnapshot_product_date"
    ON "product"."CompetitorFulfillmentSnapshot"("productId", "capturedAt");

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'CompetitorFulfillmentSnapshot_offerId_fkey'
    ) THEN
        ALTER TABLE "product"."CompetitorFulfillmentSnapshot"
            ADD CONSTRAINT "CompetitorFulfillmentSnapshot_offerId_fkey"
            FOREIGN KEY ("offerId") REFERENCES "product"."CompetitorListingOffer"("id")
            ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'CompetitorFulfillmentSnapshot_productId_fkey'
    ) THEN
        ALTER TABLE "product"."CompetitorFulfillmentSnapshot"
            ADD CONSTRAINT "CompetitorFulfillmentSnapshot_productId_fkey"
            FOREIGN KEY ("productId") REFERENCES "product"."CompetitorProduct"("id")
            ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
END $$;
