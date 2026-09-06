-- Recensioni prodotto per paese: SP-API non le espone, le copiamo dalla scheda pubblica.
CREATE TABLE "product"."StoreReviewSummary" (
    "id" TEXT NOT NULL,
    "channel" "product"."StoreChannel" NOT NULL,
    "storeKey" TEXT NOT NULL,
    "countryCode" TEXT NOT NULL,
    "asin" TEXT NOT NULL,
    "sku" TEXT,
    "capturedAt" DATE NOT NULL,
    "rating" DECIMAL(2,1) NOT NULL,
    "count" INTEGER NOT NULL,
    "histogram" JSONB,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "StoreReviewSummary_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "StoreReviewSummary_day_key" ON "product"."StoreReviewSummary"("channel", "storeKey", "asin", "capturedAt");
CREATE INDEX "StoreReviewSummary_asin_store" ON "product"."StoreReviewSummary"("asin", "storeKey");

CREATE TABLE "product"."StoreCustomerReview" (
    "id" TEXT NOT NULL,
    "channel" "product"."StoreChannel" NOT NULL,
    "storeKey" TEXT NOT NULL,
    "countryCode" TEXT NOT NULL,
    "asin" TEXT NOT NULL,
    "sku" TEXT,
    "externalId" TEXT NOT NULL,
    "rating" INTEGER NOT NULL,
    "title" TEXT NOT NULL DEFAULT '',
    "body" TEXT NOT NULL DEFAULT '',
    "author" TEXT,
    "dateLabel" TEXT NOT NULL DEFAULT '',
    "verified" BOOLEAN NOT NULL DEFAULT false,
    "capturedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "StoreCustomerReview_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "StoreCustomerReview_ext_key" ON "product"."StoreCustomerReview"("channel", "storeKey", "externalId");
CREATE INDEX "StoreCustomerReview_asin_store" ON "product"."StoreCustomerReview"("asin", "storeKey", "capturedAt");
