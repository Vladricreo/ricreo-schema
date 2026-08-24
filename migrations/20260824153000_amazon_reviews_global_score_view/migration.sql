-- Recensioni Amazon: un testo e un riassunto per ASIN, non per paese.
-- v_listing_quality_score: criteri 20+ / 4 stelle dal conteggio prodotto,
-- mai dal placeholder a 0 di Belgio/Svezia/…

-- 1) Una sola riga per (canale, id esterno)
DELETE FROM "product"."StoreCustomerReview" a
USING "product"."StoreCustomerReview" b
WHERE a.channel = b.channel
  AND a."externalId" = b."externalId"
  AND a.id > b.id;

UPDATE "product"."StoreCustomerReview"
SET "storeKey" = 'AMAZON'
WHERE channel = 'AMAZON'
  AND "storeKey" <> 'AMAZON';

DROP INDEX IF EXISTS "product"."StoreCustomerReview_ext_key";

CREATE UNIQUE INDEX "StoreCustomerReview_ext_key"
  ON "product"."StoreCustomerReview" ("channel", "externalId");

-- 2) Un riassunto Amazon per ASIN e giorno: tiene il count più alto,
-- poi riallinea storeKey. Prima si cancellano i duplicati (evita unique violation).
WITH ranked AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY upper(btrim(asin)), "capturedAt"
      ORDER BY count DESC, id
    ) AS rn
  FROM "product"."StoreReviewSummary"
  WHERE channel = 'AMAZON'
    AND asin IS NOT NULL
    AND length(btrim(asin)) > 0
)
DELETE FROM "product"."StoreReviewSummary" s
USING ranked r
WHERE s.id = r.id
  AND r.rn > 1;

DELETE FROM "product"."StoreReviewSummary"
WHERE channel = 'AMAZON'
  AND (asin IS NULL OR length(btrim(asin)) = 0);

UPDATE "product"."StoreReviewSummary"
SET
  "storeKey" = 'AMAZON',
  "countryCode" = '',
  asin = upper(btrim(asin))
WHERE channel = 'AMAZON';

-- Placeholder a 0: se l'ASIN ha già un conteggio reale, il 0 non deve vincere.
DELETE FROM "product"."StoreReviewSummary" s
WHERE s.channel = 'AMAZON'
  AND s.count = 0
  AND EXISTS (
    SELECT 1
    FROM "product"."StoreReviewSummary" o
    WHERE o.channel = 'AMAZON'
      AND o.asin = s.asin
      AND o.count > 0
  );

-- 3) Punteggio: recensioni agganciate all'ASIN (count più alto), non allo storefront
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
  SELECT DISTINCT ON (upper(btrim("asin")))
    upper(btrim("asin")) AS asin_key,
    "rating",
    "count"
  FROM "product"."StoreReviewSummary"
  WHERE "channel" = 'AMAZON'
    AND "asin" IS NOT NULL
    AND length(btrim("asin")) > 0
  ORDER BY
    upper(btrim("asin")),
    ("storeKey" = 'AMAZON') DESC,
    "count" DESC,
    "capturedAt" DESC
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
    CASE
      WHEN r."count" IS NULL THEN NULL
      ELSE r."count" >= 20
    END AS reviews_twenty_plus,
    CASE
      WHEN r."rating" IS NULL THEN NULL
      ELSE r."rating" >= 4
    END AS reviews_four_plus
  FROM latest_content c
  JOIN bullet_stats b ON b."sku" = c."sku" AND b."storeKey" = c."storeKey"
  LEFT JOIN latest_reviews r
    ON r.asin_key = upper(btrim(c."asin"))
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
