-- Matching automatico listing nostri ↔ concorrenti (titolo + immagini).
-- Solo schema product.

CREATE TYPE "product"."ListingMatchSide" AS ENUM ('OUR', 'COMPETITOR');
CREATE TYPE "product"."CompetitorMatchSuggestionStatus" AS ENUM ('PENDING', 'CONFIRMED', 'REJECTED');

ALTER TABLE "product"."CompetitorProductMatch"
    ADD COLUMN IF NOT EXISTS "ourChannel" "product"."StoreChannel" NOT NULL DEFAULT 'AMAZON',
    ADD COLUMN IF NOT EXISTS "ourExternalId" TEXT;

CREATE INDEX IF NOT EXISTS "CompetitorProductMatch_ourExternalId_idx"
    ON "product"."CompetitorProductMatch"("ourExternalId");

ALTER TABLE "product"."CompetitorProductLink"
    ADD COLUMN IF NOT EXISTS "ourChannel" "product"."StoreChannel" NOT NULL DEFAULT 'AMAZON',
    ADD COLUMN IF NOT EXISTS "ourExternalId" TEXT;

CREATE INDEX IF NOT EXISTS "CompetitorProductLink_ourChannel_ourExternalId_idx"
    ON "product"."CompetitorProductLink"("ourChannel", "ourExternalId");

CREATE TABLE IF NOT EXISTS "product"."OurListingMatchSource" (
    "id" TEXT NOT NULL,
    "channel" "product"."StoreChannel" NOT NULL,
    "externalId" TEXT NOT NULL,
    "sku" TEXT,
    "asin" TEXT,
    "title" TEXT NOT NULL,
    "imageUrl" TEXT,
    "imageUrls" JSONB,
    "ean" TEXT,
    "marketplaceKey" TEXT,
    "capturedAt" TIMESTAMPTZ(6) NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "OurListingMatchSource_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "OurListingMatchSource_channel_externalId_key"
    ON "product"."OurListingMatchSource"("channel", "externalId");
CREATE INDEX IF NOT EXISTS "OurListingMatchSource_channel_sku_idx"
    ON "product"."OurListingMatchSource"("channel", "sku");
CREATE INDEX IF NOT EXISTS "OurListingMatchSource_title_idx"
    ON "product"."OurListingMatchSource"("title");

CREATE TABLE IF NOT EXISTS "product"."ListingMatchFeature" (
    "id" TEXT NOT NULL,
    "side" "product"."ListingMatchSide" NOT NULL,
    "sourceKey" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "titleNorm" TEXT NOT NULL,
    "imageUrl" TEXT,
    "titleEmbedding" JSONB,
    "imageEmbedding" JSONB,
    "computedAt" TIMESTAMPTZ(6) NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "ListingMatchFeature_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "ListingMatchFeature_side_sourceKey_key"
    ON "product"."ListingMatchFeature"("side", "sourceKey");
CREATE INDEX IF NOT EXISTS "ListingMatchFeature_side_idx"
    ON "product"."ListingMatchFeature"("side");

CREATE TABLE IF NOT EXISTS "product"."CompetitorListingMatchSuggestion" (
    "id" TEXT NOT NULL,
    "ourChannel" "product"."StoreChannel" NOT NULL,
    "ourExternalId" TEXT NOT NULL,
    "ourSku" TEXT,
    "ourAsin" TEXT,
    "competitorProductId" TEXT NOT NULL,
    "identifierScore" DOUBLE PRECISION NOT NULL,
    "titleScore" DOUBLE PRECISION NOT NULL,
    "titleTokenScore" DOUBLE PRECISION NOT NULL,
    "imageScore" DOUBLE PRECISION NOT NULL,
    "combinedScore" DOUBLE PRECISION NOT NULL,
    "status" "product"."CompetitorMatchSuggestionStatus" NOT NULL DEFAULT 'PENDING',
    "reviewedAt" TIMESTAMPTZ(6),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "CompetitorListingMatchSuggestion_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "CompetitorListingMatchSuggestion_pair_key"
    ON "product"."CompetitorListingMatchSuggestion"("ourChannel", "ourExternalId", "competitorProductId");
CREATE INDEX IF NOT EXISTS "CompetitorListingMatchSuggestion_status_combinedScore_idx"
    ON "product"."CompetitorListingMatchSuggestion"("status", "combinedScore");
CREATE INDEX IF NOT EXISTS "CompetitorListingMatchSuggestion_our_idx"
    ON "product"."CompetitorListingMatchSuggestion"("ourChannel", "ourExternalId");
CREATE INDEX IF NOT EXISTS "CompetitorListingMatchSuggestion_competitorProductId_idx"
    ON "product"."CompetitorListingMatchSuggestion"("competitorProductId");

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'CompetitorListingMatchSuggestion_competitorProductId_fkey'
    ) THEN
        ALTER TABLE "product"."CompetitorListingMatchSuggestion"
            ADD CONSTRAINT "CompetitorListingMatchSuggestion_competitorProductId_fkey"
            FOREIGN KEY ("competitorProductId") REFERENCES "product"."CompetitorProduct"("id")
            ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS "product"."CompetitorMatchJob" (
    "id" TEXT NOT NULL,
    "phase" TEXT NOT NULL DEFAULT 'our_catalog',
    "status" "product"."StoreReportStatus" NOT NULL DEFAULT 'REQUESTED',
    "cursor" JSONB,
    "processedOur" INTEGER NOT NULL DEFAULT 0,
    "processedCompetitor" INTEGER NOT NULL DEFAULT 0,
    "processedEmbed" INTEGER NOT NULL DEFAULT 0,
    "suggestionCount" INTEGER NOT NULL DEFAULT 0,
    "totalOur" INTEGER NOT NULL DEFAULT 0,
    "totalCompetitor" INTEGER NOT NULL DEFAULT 0,
    "lastMessage" TEXT,
    "errorMessage" TEXT,
    "startedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "finishedAt" TIMESTAMPTZ(6),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "CompetitorMatchJob_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "CompetitorMatchJob_status_createdAt_idx"
    ON "product"."CompetitorMatchJob"("status", "createdAt");
