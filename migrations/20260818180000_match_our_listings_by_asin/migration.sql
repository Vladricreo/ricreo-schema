-- Accoppiamenti: più nostri listing per gruppo, identità Amazon per ASIN (non SKU).
-- Solo schema product.

CREATE TABLE IF NOT EXISTS "product"."CompetitorProductMatchOurListing" (
    "id" TEXT NOT NULL,
    "matchId" TEXT NOT NULL,
    "ourChannel" "product"."StoreChannel" NOT NULL,
    "ourExternalId" TEXT NOT NULL,
    "ourAsin" TEXT,
    "ourSku" TEXT,
    "ourMarketplaceId" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "CompetitorProductMatchOurListing_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "CompetitorProductMatchOurListing_matchId_ourChannel_ourExternalId_key"
    ON "product"."CompetitorProductMatchOurListing"("matchId", "ourChannel", "ourExternalId");
CREATE INDEX IF NOT EXISTS "CompetitorProductMatchOurListing_ourChannel_ourExternalId_idx"
    ON "product"."CompetitorProductMatchOurListing"("ourChannel", "ourExternalId");
CREATE INDEX IF NOT EXISTS "CompetitorProductMatchOurListing_ourAsin_idx"
    ON "product"."CompetitorProductMatchOurListing"("ourAsin");

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'CompetitorProductMatchOurListing_matchId_fkey'
    ) THEN
        ALTER TABLE "product"."CompetitorProductMatchOurListing"
            ADD CONSTRAINT "CompetitorProductMatchOurListing_matchId_fkey"
            FOREIGN KEY ("matchId") REFERENCES "product"."CompetitorProductMatch"("id")
            ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
END $$;

INSERT INTO "product"."CompetitorProductMatchOurListing" (
    "id",
    "matchId",
    "ourChannel",
    "ourExternalId",
    "ourAsin",
    "ourSku",
    "ourMarketplaceId",
    "createdAt",
    "updatedAt"
)
SELECT
    CONCAT('mol_', m."id"),
    m."id",
    m."ourChannel",
    COALESCE(NULLIF(m."ourExternalId", ''), NULLIF(m."ourAsin", ''), m."ourSku"),
    m."ourAsin",
    m."ourSku",
    m."ourMarketplaceId",
    m."createdAt",
    m."updatedAt"
FROM "product"."CompetitorProductMatch" m
WHERE COALESCE(NULLIF(m."ourExternalId", ''), NULLIF(m."ourAsin", ''), m."ourSku") IS NOT NULL
ON CONFLICT ("matchId", "ourChannel", "ourExternalId") DO NOTHING;

UPDATE "product"."CompetitorProductLink"
SET "ourExternalId" = COALESCE(NULLIF("ourExternalId", ''), NULLIF("ourAsin", ''), "ourSku")
WHERE "ourExternalId" IS NULL OR "ourExternalId" = '';

ALTER TABLE "product"."CompetitorProductLink"
    ALTER COLUMN "ourSku" DROP NOT NULL;

ALTER TABLE "product"."CompetitorProductLink"
    ALTER COLUMN "ourExternalId" SET NOT NULL;

DROP INDEX IF EXISTS "product"."CompetitorProductLink_productId_key";

CREATE UNIQUE INDEX IF NOT EXISTS "CompetitorProductLink_productId_ourChannel_ourExternalId_key"
    ON "product"."CompetitorProductLink"("productId", "ourChannel", "ourExternalId");

CREATE INDEX IF NOT EXISTS "OurListingMatchSource_channel_asin_idx"
    ON "product"."OurListingMatchSource"("channel", "asin");

-- Snapshot nostri listing Amazon: una riga per ASIN, non per SKU.
DO $$
DECLARE
    src RECORD;
    target_id TEXT;
    old_key TEXT;
    new_key TEXT;
BEGIN
    FOR src IN
        SELECT id, "externalId", asin
        FROM "product"."OurListingMatchSource"
        WHERE channel = 'AMAZON'
          AND asin IS NOT NULL
          AND asin <> ''
          AND "externalId" <> asin
    LOOP
        old_key := 'AMAZON:' || src."externalId";
        new_key := 'AMAZON:' || src.asin;

        SELECT id INTO target_id
        FROM "product"."OurListingMatchSource"
        WHERE channel = 'AMAZON' AND "externalId" = src.asin;

        IF target_id IS NOT NULL THEN
            DELETE FROM "product"."ListingMatchFeature"
            WHERE side = 'OUR' AND "sourceKey" = old_key;

            UPDATE "product"."CompetitorListingMatchSuggestion"
            SET "ourExternalId" = src.asin, "ourAsin" = src.asin
            WHERE "ourChannel" = 'AMAZON' AND "ourExternalId" = src."externalId"
              AND NOT EXISTS (
                  SELECT 1
                  FROM "product"."CompetitorListingMatchSuggestion" other
                  WHERE other."ourChannel" = 'AMAZON'
                    AND other."ourExternalId" = src.asin
                    AND other."competitorProductId" = "product"."CompetitorListingMatchSuggestion"."competitorProductId"
              );

            DELETE FROM "product"."CompetitorListingMatchSuggestion"
            WHERE "ourChannel" = 'AMAZON' AND "ourExternalId" = src."externalId";

            DELETE FROM "product"."OurListingMatchSource" WHERE id = src.id;
        ELSE
            UPDATE "product"."ListingMatchFeature"
            SET "sourceKey" = new_key
            WHERE side = 'OUR' AND "sourceKey" = old_key
              AND NOT EXISTS (
                  SELECT 1
                  FROM "product"."ListingMatchFeature" other
                  WHERE other.side = 'OUR' AND other."sourceKey" = new_key
              );

            DELETE FROM "product"."ListingMatchFeature"
            WHERE side = 'OUR' AND "sourceKey" = old_key;

            UPDATE "product"."CompetitorListingMatchSuggestion"
            SET "ourExternalId" = src.asin, "ourAsin" = COALESCE("ourAsin", src.asin)
            WHERE "ourChannel" = 'AMAZON' AND "ourExternalId" = src."externalId"
              AND NOT EXISTS (
                  SELECT 1
                  FROM "product"."CompetitorListingMatchSuggestion" other
                  WHERE other."ourChannel" = 'AMAZON'
                    AND other."ourExternalId" = src.asin
                    AND other."competitorProductId" = "product"."CompetitorListingMatchSuggestion"."competitorProductId"
              );

            DELETE FROM "product"."CompetitorListingMatchSuggestion"
            WHERE "ourChannel" = 'AMAZON' AND "ourExternalId" = src."externalId";

            UPDATE "product"."OurListingMatchSource"
            SET "externalId" = src.asin
            WHERE id = src.id;
        END IF;
    END LOOP;
END $$;

UPDATE "product"."CompetitorProductLink"
SET "ourExternalId" = "ourAsin"
WHERE "ourChannel" = 'AMAZON'
  AND "ourAsin" IS NOT NULL
  AND "ourAsin" <> ''
  AND "ourExternalId" <> "ourAsin"
  AND NOT EXISTS (
      SELECT 1
      FROM "product"."CompetitorProductLink" other
      WHERE other."productId" = "product"."CompetitorProductLink"."productId"
        AND other."ourChannel" = 'AMAZON'
        AND other."ourExternalId" = "product"."CompetitorProductLink"."ourAsin"
  );

UPDATE "product"."CompetitorProductMatch"
SET "ourExternalId" = "ourAsin"
WHERE "ourChannel" = 'AMAZON'
  AND "ourAsin" IS NOT NULL
  AND "ourAsin" <> ''
  AND COALESCE("ourExternalId", '') <> "ourAsin";
