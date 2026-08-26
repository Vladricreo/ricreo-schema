-- Ultima ricerca ChatGPT di uno store su Amazon / eBay / Etsy
-- per un venditore già in anagrafica su un altro canale.
-- Solo schema product.

CREATE TABLE IF NOT EXISTS "product"."CompetitorStoreResearch" (
    "id" TEXT NOT NULL,
    "competitorId" TEXT NOT NULL,
    "channel" "product"."StoreChannel" NOT NULL,
    "foundCount" INTEGER NOT NULL,
    "searchedAt" TIMESTAMPTZ(6) NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CompetitorStoreResearch_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "CompetitorStoreResearch_competitorId_channel_key"
    ON "product"."CompetitorStoreResearch"("competitorId", "channel");

CREATE INDEX IF NOT EXISTS "CompetitorStoreResearch_competitorId_searchedAt_idx"
    ON "product"."CompetitorStoreResearch"("competitorId", "searchedAt");

ALTER TABLE "product"."CompetitorStoreResearch"
    ADD CONSTRAINT "CompetitorStoreResearch_competitorId_fkey"
    FOREIGN KEY ("competitorId") REFERENCES "product"."Competitor"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
