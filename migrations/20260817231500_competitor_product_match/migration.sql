-- Gruppo "stesso prodotto" fra seller, con collegamento opzionale al nostro listing.
-- Solo schema product.

CREATE TABLE "product"."CompetitorProductMatch" (
    "id" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "asin" TEXT,
    "ean" TEXT,
    "gtin" TEXT,
    "ourSku" TEXT,
    "ourAsin" TEXT,
    "ourMarketplaceId" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "CompetitorProductMatch_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "CompetitorProductMatch_ourSku_idx" ON "product"."CompetitorProductMatch"("ourSku");
CREATE INDEX "CompetitorProductMatch_ourAsin_idx" ON "product"."CompetitorProductMatch"("ourAsin");
CREATE INDEX "CompetitorProductMatch_ean_idx" ON "product"."CompetitorProductMatch"("ean");
CREATE INDEX "CompetitorProductMatch_asin_idx" ON "product"."CompetitorProductMatch"("asin");

ALTER TABLE "product"."CompetitorProduct"
    ADD COLUMN "matchId" TEXT;

CREATE INDEX "CompetitorProduct_matchId_idx" ON "product"."CompetitorProduct"("matchId");

ALTER TABLE "product"."CompetitorProduct"
    ADD CONSTRAINT "CompetitorProduct_matchId_fkey"
    FOREIGN KEY ("matchId") REFERENCES "product"."CompetitorProductMatch"("id")
    ON DELETE SET NULL ON UPDATE CASCADE;

-- Porta i collegamenti già fatti al nostro listing dentro un gruppo (un prodotto ciascuno).
INSERT INTO "product"."CompetitorProductMatch" (
    "id", "title", "asin", "ean", "gtin", "ourSku", "ourAsin", "ourMarketplaceId", "createdAt", "updatedAt"
)
SELECT
    'match_' || p."id",
    p."title",
    p."asin",
    p."ean",
    p."gtin",
    l."ourSku",
    l."ourAsin",
    l."ourMarketplaceId",
    l."createdAt",
    l."updatedAt"
FROM "product"."CompetitorProductLink" l
JOIN "product"."CompetitorProduct" p ON p."id" = l."productId";

UPDATE "product"."CompetitorProduct" p
SET "matchId" = 'match_' || p."id"
WHERE EXISTS (
    SELECT 1 FROM "product"."CompetitorProductLink" l WHERE l."productId" = p."id"
);
