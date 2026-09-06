-- Storico Amazon dei prodotti concorrenti: BSR giornaliero, vendite, recensioni.
-- Solo schema product. Non tocca inventory / print-farm.

CREATE TABLE "product"."CompetitorBsrSnapshot" (
    "id" TEXT NOT NULL,
    "productId" TEXT NOT NULL,
    "countryCode" TEXT NOT NULL,
    "marketplaceKey" TEXT NOT NULL,
    "capturedAt" DATE NOT NULL,
    "category" TEXT NOT NULL,
    "categoryKey" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "rank" INTEGER NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "CompetitorBsrSnapshot_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "CompetitorBsrSnapshot_rank_key"
    ON "product"."CompetitorBsrSnapshot"("productId", "marketplaceKey", "capturedAt", "kind", "categoryKey");
CREATE INDEX "CompetitorBsrSnapshot_product_date"
    ON "product"."CompetitorBsrSnapshot"("productId", "capturedAt");
CREATE INDEX "CompetitorBsrSnapshot_country_date"
    ON "product"."CompetitorBsrSnapshot"("countryCode", "capturedAt");

CREATE TABLE "product"."CompetitorSalesDaily" (
    "id" TEXT NOT NULL,
    "productId" TEXT NOT NULL,
    "countryCode" TEXT NOT NULL,
    "marketplaceKey" TEXT NOT NULL,
    "soldOn" DATE NOT NULL,
    "units" INTEGER NOT NULL,
    "revenue" DECIMAL(12,2),
    "currency" TEXT NOT NULL DEFAULT 'EUR',
    "source" TEXT NOT NULL DEFAULT 'MANUAL',
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "CompetitorSalesDaily_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "CompetitorSalesDaily_day_key"
    ON "product"."CompetitorSalesDaily"("productId", "marketplaceKey", "soldOn");
CREATE INDEX "CompetitorSalesDaily_product_date"
    ON "product"."CompetitorSalesDaily"("productId", "soldOn");

CREATE TABLE "product"."CompetitorReviewSummary" (
    "id" TEXT NOT NULL,
    "productId" TEXT NOT NULL,
    "countryCode" TEXT NOT NULL,
    "marketplaceKey" TEXT NOT NULL,
    "capturedAt" DATE NOT NULL,
    "rating" DECIMAL(2,1) NOT NULL,
    "count" INTEGER NOT NULL,
    "histogram" JSONB,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "CompetitorReviewSummary_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "CompetitorReviewSummary_day_key"
    ON "product"."CompetitorReviewSummary"("productId", "marketplaceKey", "capturedAt");
CREATE INDEX "CompetitorReviewSummary_product_date"
    ON "product"."CompetitorReviewSummary"("productId", "capturedAt");

CREATE TABLE "product"."CompetitorCustomerReview" (
    "id" TEXT NOT NULL,
    "productId" TEXT NOT NULL,
    "countryCode" TEXT NOT NULL,
    "marketplaceKey" TEXT NOT NULL,
    "externalId" TEXT NOT NULL,
    "rating" INTEGER NOT NULL,
    "title" TEXT NOT NULL DEFAULT '',
    "body" TEXT NOT NULL DEFAULT '',
    "author" TEXT,
    "dateLabel" TEXT NOT NULL DEFAULT '',
    "reviewedAt" DATE,
    "originCountryCode" TEXT,
    "verified" BOOLEAN NOT NULL DEFAULT false,
    "capturedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "CompetitorCustomerReview_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "CompetitorCustomerReview_ext_key"
    ON "product"."CompetitorCustomerReview"("productId", "marketplaceKey", "externalId");
CREATE INDEX "CompetitorCustomerReview_product_date"
    ON "product"."CompetitorCustomerReview"("productId", "reviewedAt");

ALTER TABLE "product"."CompetitorBsrSnapshot"
    ADD CONSTRAINT "CompetitorBsrSnapshot_productId_fkey"
    FOREIGN KEY ("productId") REFERENCES "product"."CompetitorProduct"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "product"."CompetitorSalesDaily"
    ADD CONSTRAINT "CompetitorSalesDaily_productId_fkey"
    FOREIGN KEY ("productId") REFERENCES "product"."CompetitorProduct"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "product"."CompetitorReviewSummary"
    ADD CONSTRAINT "CompetitorReviewSummary_productId_fkey"
    FOREIGN KEY ("productId") REFERENCES "product"."CompetitorProduct"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "product"."CompetitorCustomerReview"
    ADD CONSTRAINT "CompetitorCustomerReview_productId_fkey"
    FOREIGN KEY ("productId") REFERENCES "product"."CompetitorProduct"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
