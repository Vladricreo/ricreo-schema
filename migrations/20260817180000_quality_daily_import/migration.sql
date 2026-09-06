-- Import giornaliero qualità: snapshot contenuti, recensioni (data/paese/presa visione),
-- job resumable e view del breakdown punteggio per paese.

ALTER TABLE "product"."StoreCustomerReview"
  ADD COLUMN IF NOT EXISTS "reviewedAt" DATE,
  ADD COLUMN IF NOT EXISTS "originCountryCode" TEXT,
  ADD COLUMN IF NOT EXISTS "viewed" BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS "StoreCustomerReview_viewed_date"
  ON "product"."StoreCustomerReview" ("viewed", "reviewedAt");

CREATE TABLE IF NOT EXISTS "product"."StoreListingContentSnapshot" (
  "id" TEXT NOT NULL,
  "channel" "product"."StoreChannel" NOT NULL,
  "storeKey" TEXT NOT NULL,
  "countryCode" TEXT NOT NULL,
  "sku" TEXT NOT NULL,
  "asin" TEXT,
  "capturedAt" DATE NOT NULL,
  "title" TEXT NOT NULL DEFAULT '',
  "description" TEXT NOT NULL DEFAULT '',
  "bulletPoints" JSONB NOT NULL,
  "productImages" JSONB NOT NULL,
  "mainImageWidth" INTEGER,
  "mainImageHeight" INTEGER,
  "hasVideo" BOOLEAN NOT NULL DEFAULT false,
  "hasAplus" BOOLEAN NOT NULL DEFAULT false,
  "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMPTZ(6) NOT NULL,

  CONSTRAINT "StoreListingContentSnapshot_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "StoreListingContent_day_key"
  ON "product"."StoreListingContentSnapshot" ("channel", "storeKey", "sku", "capturedAt");
CREATE INDEX IF NOT EXISTS "StoreListingContent_sku_date"
  ON "product"."StoreListingContentSnapshot" ("sku", "capturedAt");
CREATE INDEX IF NOT EXISTS "StoreListingContent_asin_store_date"
  ON "product"."StoreListingContentSnapshot" ("asin", "storeKey", "capturedAt");

CREATE TABLE IF NOT EXISTS "product"."StoreQualityDailyJob" (
  "id" TEXT NOT NULL,
  "channel" "product"."StoreChannel" NOT NULL,
  "capturedAt" DATE NOT NULL,
  "phase" TEXT NOT NULL DEFAULT 'listings',
  "nextAmazonPage" INTEGER NOT NULL DEFAULT 1,
  "processedListings" INTEGER NOT NULL DEFAULT 0,
  "processedReviews" INTEGER NOT NULL DEFAULT 0,
  "totalListings" INTEGER NOT NULL DEFAULT 0,
  "status" "product"."StoreReportStatus" NOT NULL DEFAULT 'REQUESTED',
  "lastMessage" TEXT,
  "errorMessage" TEXT,
  "importedAt" TIMESTAMPTZ(6),
  "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMPTZ(6) NOT NULL,

  CONSTRAINT "StoreQualityDailyJob_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "StoreQualityDailyJob_day_key"
  ON "product"."StoreQualityDailyJob" ("channel", "capturedAt");
CREATE INDEX IF NOT EXISTS "StoreQualityDailyJob_status_idx"
  ON "product"."StoreQualityDailyJob" ("status", "capturedAt");

DROP VIEW IF EXISTS "product"."v_listing_quality_score";

CREATE VIEW "product"."v_listing_quality_score"
WITH (security_invoker = true) AS
WITH latest_content AS (
  SELECT DISTINCT ON ("sku", "storeKey")
    "sku",
    "storeKey",
    "countryCode",
    "asin",
    "capturedAt",
    "title",
    "description",
    "bulletPoints",
    "productImages",
    "mainImageWidth",
    "mainImageHeight",
    "hasVideo",
    "hasAplus"
  FROM "product"."StoreListingContentSnapshot"
  WHERE "channel" = 'AMAZON'
  ORDER BY "sku", "storeKey", "capturedAt" DESC
),
latest_reviews AS (
  SELECT DISTINCT ON ("asin", "storeKey")
    "asin",
    "storeKey",
    "rating",
    "count"
  FROM "product"."StoreReviewSummary"
  WHERE "channel" = 'AMAZON'
  ORDER BY "asin", "storeKey", "capturedAt" DESC
),
bullet_stats AS (
  SELECT
    c."sku",
    c."storeKey",
    COALESCE(jsonb_array_length(c."bulletPoints"), 0) AS bullet_count,
    COALESCE((
      SELECT bool_and(length(b.val) > 150)
      FROM jsonb_array_elements_text(c."bulletPoints") AS b(val)
    ), false) AS all_over_150,
    COALESCE((
      SELECT bool_and(
        substring(b.val FROM '[[:alpha:]]') ~ '[[:upper:]]'
      )
      FROM jsonb_array_elements_text(c."bulletPoints") AS b(val)
    ), false) AS all_capitalized,
    COALESCE((
      SELECT bool_and(
        NOT (
          length(regexp_replace(b.val, '[^[:alpha:]]', '', 'g')) >= 8
          AND regexp_replace(b.val, '[^[:alpha:]]', '', 'g')
            = upper(regexp_replace(b.val, '[^[:alpha:]]', '', 'g'))
        )
      )
      FROM jsonb_array_elements_text(c."bulletPoints") AS b(val)
    ), false) AS none_all_caps
  FROM latest_content c
),
checks AS (
  SELECT
    c."sku",
    c."storeKey",
    c."countryCode",
    c."asin",
    c."capturedAt",
    CASE
      WHEN length(c."title") = 0 THEN NULL
      ELSE c."title" !~ '[★☆●◆■□▪▫®™©!?#$^*_\={}[\]\\|<>~`]'
    END AS title_no_symbols,
    CASE
      WHEN length(c."title") = 0 THEN NULL
      ELSE length(c."title") > 150
    END AS title_over_150,
    CASE
      WHEN b.bullet_count > 0 THEN b.bullet_count >= 5
      ELSE false
    END AS bullets_five_or_more,
    CASE
      WHEN b.bullet_count > 0 THEN b.all_over_150
      ELSE false
    END AS bullets_over_150,
    CASE
      WHEN b.bullet_count > 0 THEN b.all_capitalized
      ELSE false
    END AS bullets_capitalized,
    CASE
      WHEN b.bullet_count > 0 THEN b.none_all_caps
      ELSE false
    END AS bullets_not_all_caps,
    CASE
      WHEN length(c."description") > 0 OR c."hasAplus" THEN length(c."description") > 1000 OR c."hasAplus"
      ELSE false
    END AS description_over_1000,
    CASE
      WHEN c."mainImageWidth" IS NOT NULL AND c."mainImageHeight" IS NOT NULL
        THEN c."mainImageWidth" >= 1000 AND c."mainImageHeight" >= 1000
      ELSE NULL
    END AS media_resolution,
    NULL::boolean AS media_white_bg,
    COALESCE(jsonb_array_length(c."productImages"), 0) >= 7 AS media_seven_plus,
    c."hasVideo" AS media_has_video,
    CASE WHEN r."count" IS NULL THEN NULL ELSE r."count" >= 20 END AS reviews_twenty_plus,
    CASE WHEN r."rating" IS NULL THEN NULL ELSE r."rating" >= 4 END AS reviews_four_plus
  FROM latest_content c
  JOIN bullet_stats b ON b."sku" = c."sku" AND b."storeKey" = c."storeKey"
  LEFT JOIN latest_reviews r ON r."asin" = c."asin" AND r."storeKey" = c."storeKey"
)
SELECT
  (ch."sku" || '|' || ch."storeKey") AS "id",
  ch."sku",
  ch."storeKey",
  ch."countryCode",
  ch."asin",
  ch."capturedAt",
  CASE
    WHEN (
      (ch.title_no_symbols IS NOT NULL)::int
      + (ch.title_over_150 IS NOT NULL)::int
      + 1 + 1 + 1 + 1 + 1
      + (ch.media_resolution IS NOT NULL)::int
      + 0
      + 1 + 1
      + (ch.reviews_twenty_plus IS NOT NULL)::int
      + (ch.reviews_four_plus IS NOT NULL)::int
    ) = 0 THEN 0
    ELSE round((
      (
        (ch.title_no_symbols IS TRUE)::int
        + (ch.title_over_150 IS TRUE)::int
        + (ch.bullets_five_or_more IS TRUE)::int
        + (ch.bullets_over_150 IS TRUE)::int
        + (ch.bullets_capitalized IS TRUE)::int
        + (ch.bullets_not_all_caps IS TRUE)::int
        + (ch.description_over_1000 IS TRUE)::int
        + (ch.media_resolution IS TRUE)::int
        + (ch.media_seven_plus IS TRUE)::int
        + (ch.media_has_video IS TRUE)::int
        + (ch.reviews_twenty_plus IS TRUE)::int
        + (ch.reviews_four_plus IS TRUE)::int
      )::numeric
      / (
        (ch.title_no_symbols IS NOT NULL)::int
        + (ch.title_over_150 IS NOT NULL)::int
        + 5
        + (ch.media_resolution IS NOT NULL)::int
        + 2
        + (ch.reviews_twenty_plus IS NOT NULL)::int
        + (ch.reviews_four_plus IS NOT NULL)::int
      )
    ) * 10, 1)
  END AS "listingScore",
  (
    (ch.title_no_symbols IS NOT NULL)::int
    + (ch.title_over_150 IS NOT NULL)::int
    + 5
    + (ch.media_resolution IS NOT NULL)::int
    + 2
    + (ch.reviews_twenty_plus IS NOT NULL)::int
    + (ch.reviews_four_plus IS NOT NULL)::int
  ) AS "scoreKnown",
  (
    (ch.title_no_symbols IS TRUE)::int
    + (ch.title_over_150 IS TRUE)::int
    + (ch.bullets_five_or_more IS TRUE)::int
    + (ch.bullets_over_150 IS TRUE)::int
    + (ch.bullets_capitalized IS TRUE)::int
    + (ch.bullets_not_all_caps IS TRUE)::int
    + (ch.description_over_1000 IS TRUE)::int
    + (ch.media_resolution IS TRUE)::int
    + (ch.media_seven_plus IS TRUE)::int
    + (ch.media_has_video IS TRUE)::int
    + (ch.reviews_twenty_plus IS TRUE)::int
    + (ch.reviews_four_plus IS TRUE)::int
  ) AS "scorePassed",
  ch.title_no_symbols AS "titleNoSymbols",
  ch.title_over_150 AS "titleOver150Chars",
  ch.bullets_five_or_more AS "bulletsFiveOrMore",
  ch.bullets_over_150 AS "bulletsOver150CharsEach",
  ch.bullets_capitalized AS "bulletsCapitalizedFirst",
  ch.bullets_not_all_caps AS "bulletsNotAllCaps",
  ch.description_over_1000 AS "descriptionOver1000Chars",
  ch.media_resolution AS "mediaCorrectResolution",
  ch.media_white_bg AS "mediaWhiteBackground",
  ch.media_seven_plus AS "mediaSevenPlusImages",
  ch.media_has_video AS "mediaHasVideo",
  ch.reviews_twenty_plus AS "reviewsTwentyPlus",
  ch.reviews_four_plus AS "reviewsFourPlusRating"
FROM checks ch;
