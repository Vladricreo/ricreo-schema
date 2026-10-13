-- Avvisi Amazon correnti (issues ERROR / WARNING) per SKU × paese.
-- Scritti dall'import giornaliero qualità (searchListingsItems con `issues`):
-- a ogni osservazione le righe di quella SKU sui paesi richiesti vengono
-- sostituite. Letti da /dashboard/listings nel riepilogo «Problemi per paese».

-- CreateTable
CREATE TABLE "product"."StoreListingIssue" (
    "id" TEXT NOT NULL,
    "channel" "product"."StoreChannel" NOT NULL,
    "storeKey" TEXT NOT NULL,
    "countryCode" TEXT NOT NULL,
    "sku" TEXT NOT NULL,
    "asin" TEXT,
    "code" TEXT NOT NULL,
    "severity" TEXT NOT NULL,
    "message" TEXT NOT NULL,
    "observedAt" TIMESTAMPTZ(6) NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "StoreListingIssue_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "StoreListingIssue_store_sku"
  ON "product"."StoreListingIssue" ("channel", "storeKey", "sku");

-- CreateIndex
CREATE INDEX "StoreListingIssue_country_observed"
  ON "product"."StoreListingIssue" ("countryCode", "observedAt");
