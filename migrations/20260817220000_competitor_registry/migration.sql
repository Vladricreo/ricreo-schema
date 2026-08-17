-- Anagrafica seller concorrenti e catalogo per canale (schema product).
-- Non tocca inventory / print-farm.

CREATE TYPE "product"."CompetitorLegalType" AS ENUM ('PRIVATO', 'PARTITA_IVA');

CREATE TYPE "product"."CompetitorStatus" AS ENUM ('ACTIVE', 'ARCHIVED');

CREATE TYPE "product"."CompetitorListingStatus" AS ENUM ('ACTIVE', 'CLOSED');

CREATE TABLE "product"."Competitor" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "legalType" "product"."CompetitorLegalType" NOT NULL,
    "vatNumber" TEXT,
    "city" TEXT NOT NULL,
    "countryCode" TEXT NOT NULL,
    "country" TEXT NOT NULL,
    "status" "product"."CompetitorStatus" NOT NULL DEFAULT 'ACTIVE',
    "notes" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "Competitor_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "Competitor_status_idx" ON "product"."Competitor"("status");
CREATE INDEX "Competitor_name_idx" ON "product"."Competitor"("name");
CREATE INDEX "Competitor_countryCode_idx" ON "product"."Competitor"("countryCode");

CREATE TABLE "product"."CompetitorChannel" (
    "id" TEXT NOT NULL,
    "competitorId" TEXT NOT NULL,
    "channel" "product"."StoreChannel" NOT NULL,
    "storeId" TEXT NOT NULL,
    "storeName" TEXT,
    "storeUrl" TEXT,
    "lastFetchedAt" TIMESTAMPTZ(6),
    "lastFetchError" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "CompetitorChannel_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "CompetitorChannel_competitorId_channel_storeId_key"
    ON "product"."CompetitorChannel"("competitorId", "channel", "storeId");
CREATE INDEX "CompetitorChannel_channel_storeId_idx"
    ON "product"."CompetitorChannel"("channel", "storeId");

CREATE TABLE "product"."CompetitorRevenueYear" (
    "id" TEXT NOT NULL,
    "competitorId" TEXT NOT NULL,
    "year" INTEGER NOT NULL,
    "amount" DECIMAL(14,2) NOT NULL,
    "currency" TEXT NOT NULL DEFAULT 'EUR',
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "CompetitorRevenueYear_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "CompetitorRevenueYear_competitorId_year_key"
    ON "product"."CompetitorRevenueYear"("competitorId", "year");
CREATE INDEX "CompetitorRevenueYear_year_idx" ON "product"."CompetitorRevenueYear"("year");

CREATE TABLE "product"."CompetitorProduct" (
    "id" TEXT NOT NULL,
    "competitorId" TEXT NOT NULL,
    "competitorChannelId" TEXT NOT NULL,
    "identityKey" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "asin" TEXT,
    "sku" TEXT,
    "ean" TEXT,
    "gtin" TEXT,
    "brand" TEXT,
    "imageUrl" TEXT,
    "estimatedUnitsSold" INTEGER,
    "publishedAt" TIMESTAMPTZ(6),
    "listingUpdatedAt" TIMESTAMPTZ(6),
    "closedAt" TIMESTAMPTZ(6),
    "lastFetchedAt" TIMESTAMPTZ(6),
    "status" "product"."CompetitorListingStatus" NOT NULL DEFAULT 'ACTIVE',
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "CompetitorProduct_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "CompetitorProduct_competitorChannelId_identityKey_key"
    ON "product"."CompetitorProduct"("competitorChannelId", "identityKey");
CREATE INDEX "CompetitorProduct_competitorId_status_idx"
    ON "product"."CompetitorProduct"("competitorId", "status");
CREATE INDEX "CompetitorProduct_asin_idx" ON "product"."CompetitorProduct"("asin");
CREATE INDEX "CompetitorProduct_sku_idx" ON "product"."CompetitorProduct"("sku");
CREATE INDEX "CompetitorProduct_ean_idx" ON "product"."CompetitorProduct"("ean");

CREATE TABLE "product"."CompetitorListingOffer" (
    "id" TEXT NOT NULL,
    "productId" TEXT NOT NULL,
    "countryCode" TEXT NOT NULL,
    "marketplaceKey" TEXT NOT NULL,
    "externalItemId" TEXT,
    "title" TEXT NOT NULL,
    "listingUrl" TEXT,
    "price" DECIMAL(12,2),
    "shippingPrice" DECIMAL(12,2),
    "currency" TEXT NOT NULL DEFAULT 'EUR',
    "publishedAt" TIMESTAMPTZ(6),
    "listingUpdatedAt" TIMESTAMPTZ(6),
    "closedAt" TIMESTAMPTZ(6),
    "lastFetchedAt" TIMESTAMPTZ(6),
    "status" "product"."CompetitorListingStatus" NOT NULL DEFAULT 'ACTIVE',
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "CompetitorListingOffer_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "CompetitorListingOffer_productId_marketplaceKey_key"
    ON "product"."CompetitorListingOffer"("productId", "marketplaceKey");
CREATE INDEX "CompetitorListingOffer_countryCode_idx"
    ON "product"."CompetitorListingOffer"("countryCode");
CREATE INDEX "CompetitorListingOffer_externalItemId_idx"
    ON "product"."CompetitorListingOffer"("externalItemId");

CREATE TABLE "product"."CompetitorPriceSnapshot" (
    "id" TEXT NOT NULL,
    "offerId" TEXT NOT NULL,
    "capturedAt" DATE NOT NULL,
    "price" DECIMAL(12,2),
    "shippingPrice" DECIMAL(12,2),
    "currency" TEXT NOT NULL DEFAULT 'EUR',
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CompetitorPriceSnapshot_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "CompetitorPriceSnapshot_offerId_capturedAt_key"
    ON "product"."CompetitorPriceSnapshot"("offerId", "capturedAt");
CREATE INDEX "CompetitorPriceSnapshot_capturedAt_idx"
    ON "product"."CompetitorPriceSnapshot"("capturedAt");

CREATE TABLE "product"."CompetitorProductLink" (
    "id" TEXT NOT NULL,
    "productId" TEXT NOT NULL,
    "ourSku" TEXT NOT NULL,
    "ourAsin" TEXT,
    "ourMarketplaceId" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "CompetitorProductLink_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "CompetitorProductLink_productId_key"
    ON "product"."CompetitorProductLink"("productId");
CREATE INDEX "CompetitorProductLink_ourSku_idx" ON "product"."CompetitorProductLink"("ourSku");
CREATE INDEX "CompetitorProductLink_ourAsin_idx" ON "product"."CompetitorProductLink"("ourAsin");

ALTER TABLE "product"."CompetitorChannel"
    ADD CONSTRAINT "CompetitorChannel_competitorId_fkey"
    FOREIGN KEY ("competitorId") REFERENCES "product"."Competitor"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "product"."CompetitorRevenueYear"
    ADD CONSTRAINT "CompetitorRevenueYear_competitorId_fkey"
    FOREIGN KEY ("competitorId") REFERENCES "product"."Competitor"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "product"."CompetitorProduct"
    ADD CONSTRAINT "CompetitorProduct_competitorId_fkey"
    FOREIGN KEY ("competitorId") REFERENCES "product"."Competitor"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "product"."CompetitorProduct"
    ADD CONSTRAINT "CompetitorProduct_competitorChannelId_fkey"
    FOREIGN KEY ("competitorChannelId") REFERENCES "product"."CompetitorChannel"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "product"."CompetitorListingOffer"
    ADD CONSTRAINT "CompetitorListingOffer_productId_fkey"
    FOREIGN KEY ("productId") REFERENCES "product"."CompetitorProduct"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "product"."CompetitorPriceSnapshot"
    ADD CONSTRAINT "CompetitorPriceSnapshot_offerId_fkey"
    FOREIGN KEY ("offerId") REFERENCES "product"."CompetitorListingOffer"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "product"."CompetitorProductLink"
    ADD CONSTRAINT "CompetitorProductLink_productId_fkey"
    FOREIGN KEY ("productId") REFERENCES "product"."CompetitorProduct"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
