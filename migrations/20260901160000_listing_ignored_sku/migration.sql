-- SKU dismessi: ignore list globale + esclusioni nelle view/matview salute listing.
-- Lo storico ordini e le matview overview/sales analytics restano invariati.

CREATE TABLE IF NOT EXISTS "product"."ListingIgnoredSku" (
    "id" TEXT NOT NULL,
    "sku" TEXT NOT NULL,
    "reason" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ListingIgnoredSku_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "ListingIgnoredSku_sku"
    ON "product"."ListingIgnoredSku" ("sku");

-- View/matview salute: drop in ordine di dipendenza, poi ricreo con filtro ignore.
DROP MATERIALIZED VIEW IF EXISTS "product"."mv_listing_health_store_stats";
DROP MATERIALIZED VIEW IF EXISTS "product"."mv_listing_review_alert";
DROP MATERIALIZED VIEW IF EXISTS "product"."mv_listing_bsr_trend";
DROP MATERIALIZED VIEW IF EXISTS "product"."mv_listing_sales_returns_30d";
DROP MATERIALIZED VIEW IF EXISTS "product"."mv_listing_health_current";

DROP VIEW IF EXISTS "product"."v_listing_review_alert";
DROP VIEW IF EXISTS "product"."v_listing_bsr_trend";
DROP VIEW IF EXISTS "product"."v_listing_sales_returns_30d";
DROP VIEW IF EXISTS "product"."v_listing_health_current";
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
    AND NOT EXISTS (
      SELECT 1 FROM product."ListingIgnoredSku" i
      WHERE lower(i.sku) = lower("StoreListingContentSnapshot"."sku")
    )
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

CREATE VIEW "product"."v_listing_health_current"
WITH (security_invoker = true) AS
WITH latest_content AS (
  SELECT DISTINCT ON ("channel", "storeKey", "sku")
    "channel",
    "storeKey",
    "countryCode",
    "sku",
    "asin",
    "title",
    "inventoryProductId",
    "inventoryProductName",
    "capturedAt"
  FROM "product"."StoreListingContentSnapshot"
  WHERE NOT EXISTS (
    SELECT 1 FROM product."ListingIgnoredSku" i
    WHERE lower(i.sku) = lower("StoreListingContentSnapshot"."sku")
  )
  ORDER BY "channel", "storeKey", "sku", "capturedAt" DESC
),
latest_activity AS (
  SELECT DISTINCT ON ("channel", "storeKey", "sku")
    "channel",
    "storeKey",
    "sku",
    "isBuyable",
    "isDiscoverable",
    "isPublished",
    "quantity",
    "capturedAt" AS "activityCapturedAt"
  FROM "product"."StoreListingActivitySnapshot"
  ORDER BY "channel", "storeKey", "sku", "capturedAt" DESC
),
open_inactivity AS (
  SELECT DISTINCT ON ("channel", "storeKey", "sku")
    "channel",
    "storeKey",
    "sku",
    "reason" AS "inactivityReason",
    "startedAt" AS "inactivityStartedAt"
  FROM "product"."StoreListingInactivityPeriod"
  WHERE "endedAt" IS NULL
  ORDER BY "channel", "storeKey", "sku", "startedAt" ASC
)
SELECT
  (c."channel"::text || '|' || c."storeKey" || '|' || c."sku") AS "id",
  c."channel",
  c."storeKey",
  c."countryCode",
  c."sku",
  c."asin",
  c."title",
  c."inventoryProductId",
  c."inventoryProductName",
  c."capturedAt",
  a."isBuyable",
  a."isDiscoverable",
  a."isPublished",
  a."quantity",
  a."activityCapturedAt",
  i."inactivityReason",
  i."inactivityStartedAt",
  q."listingScore",
  p."listingPrice",
  p."currency"
FROM latest_content c
LEFT JOIN latest_activity a
  ON a."channel" = c."channel"
 AND a."storeKey" = c."storeKey"
 AND a."sku" = c."sku"
LEFT JOIN open_inactivity i
  ON i."channel" = c."channel"
 AND i."storeKey" = c."storeKey"
 AND i."sku" = c."sku"
LEFT JOIN "product"."v_listing_quality_score" q
  ON q."sku" = c."sku"
 AND q."storeKey" = c."storeKey"
LEFT JOIN "product"."ListingProfitEstimate" p
  ON p."channel" = c."channel"
 AND p."storeKey" = c."storeKey"
 AND p."sku" = c."sku";

CREATE VIEW "product"."v_listing_sales_returns_30d"
WITH (security_invoker = true) AS
WITH sales AS (
  SELECT
    "channel",
    "storeKey",
    "sku",
    SUM(CASE WHEN "date" >= (CURRENT_DATE - 30) THEN "unitsOrdered" ELSE 0 END)::int AS "units30",
    SUM(CASE WHEN "date" >= (CURRENT_DATE - 60) AND "date" < (CURRENT_DATE - 30) THEN "unitsOrdered" ELSE 0 END)::int AS "unitsPrev30",
    SUM(CASE WHEN "date" >= (CURRENT_DATE - 30) THEN "orderedProductSales" ELSE 0 END) AS "revenue30",
    MAX("asin") AS "asin",
    MAX("productName") AS "productName"
  FROM "product"."StoreSalesDaily"
  WHERE "date" >= (CURRENT_DATE - 60)
    AND NOT EXISTS (
      SELECT 1 FROM product."ListingIgnoredSku" i
      WHERE lower(i.sku) = lower("StoreSalesDaily"."sku")
    )
  GROUP BY 1, 2, 3
),
returns AS (
  SELECT
    "channel",
    "storeKey",
    "sku",
    SUM(CASE WHEN "returnDate" >= (CURRENT_DATE - 30) THEN "quantity" ELSE 0 END)::int AS "returns30",
    SUM(CASE WHEN "returnDate" >= (CURRENT_DATE - 60) AND "returnDate" < (CURRENT_DATE - 30) THEN "quantity" ELSE 0 END)::int AS "returnsPrev30"
  FROM "product"."StoreReturnLine"
  WHERE "returnDate" >= (CURRENT_DATE - 60)
    AND NOT EXISTS (
      SELECT 1 FROM product."ListingIgnoredSku" i
      WHERE lower(i.sku) = lower("StoreReturnLine"."sku")
    )
  GROUP BY 1, 2, 3
),
top_reason AS (
  SELECT DISTINCT ON (g."channel", g."storeKey", g."sku")
    g."channel",
    g."storeKey",
    g."sku",
    g."reason" AS "topReturnReason"
  FROM (
    SELECT
      "channel",
      "storeKey",
      "sku",
      COALESCE(NULLIF(trim("reason"), ''), 'Motivo non specificato') AS "reason",
      SUM("quantity") AS qty
    FROM "product"."StoreReturnLine"
    WHERE "returnDate" >= (CURRENT_DATE - 30)
      AND NOT EXISTS (
        SELECT 1 FROM product."ListingIgnoredSku" i
        WHERE lower(i.sku) = lower("StoreReturnLine"."sku")
      )
    GROUP BY 1, 2, 3, 4
  ) g
  ORDER BY g."channel", g."storeKey", g."sku", g.qty DESC
)
SELECT
  (s."channel"::text || '|' || s."storeKey" || '|' || s."sku") AS "id",
  s."channel",
  s."storeKey",
  s."sku",
  s."asin",
  s."productName",
  s."units30",
  s."unitsPrev30",
  s."revenue30",
  COALESCE(r."returns30", 0) AS "returns30",
  COALESCE(r."returnsPrev30", 0) AS "returnsPrev30",
  CASE
    WHEN s."units30" > 0 THEN round((COALESCE(r."returns30", 0)::numeric / s."units30") * 100, 2)
    ELSE 0
  END AS "returnRate30",
  CASE
    WHEN s."unitsPrev30" > 0 THEN round((COALESCE(r."returnsPrev30", 0)::numeric / s."unitsPrev30") * 100, 2)
    ELSE 0
  END AS "returnRatePrev30",
  tr."topReturnReason"
FROM sales s
LEFT JOIN returns r
  ON r."channel" = s."channel"
 AND r."storeKey" = s."storeKey"
 AND r."sku" = s."sku"
LEFT JOIN top_reason tr
  ON tr."channel" = s."channel"
 AND tr."storeKey" = s."storeKey"
 AND tr."sku" = s."sku";

CREATE VIEW "product"."v_listing_bsr_trend"
WITH (security_invoker = true) AS
WITH primary_rank AS (
  SELECT DISTINCT ON ("storeKey", "asin", "capturedAt")
    "storeKey",
    "asin",
    "sku",
    "countryCode",
    "capturedAt",
    "rank",
    "category",
    "categoryKey"
  FROM "product"."StoreBsrSnapshot"
  WHERE "channel" = 'AMAZON'
  ORDER BY "storeKey", "asin", "capturedAt" DESC, "rank" ASC
),
latest AS (
  SELECT DISTINCT ON ("storeKey", "asin") *
  FROM primary_rank
  ORDER BY "storeKey", "asin", "capturedAt" DESC
),
baseline AS (
  SELECT DISTINCT ON (p."storeKey", p."asin")
    p."storeKey",
    p."asin",
    p."rank" AS "prevRank",
    p."capturedAt" AS "prevCapturedAt"
  FROM primary_rank p
  JOIN latest l
    ON l."storeKey" = p."storeKey"
   AND l."asin" = p."asin"
  WHERE p."capturedAt" < l."capturedAt"
  ORDER BY p."storeKey", p."asin", p."capturedAt" ASC
)
SELECT
  (l."storeKey" || '|' || l."asin") AS "id",
  'AMAZON'::"product"."StoreChannel" AS "channel",
  l."storeKey",
  l."countryCode",
  l."asin",
  l."sku",
  l."capturedAt",
  l."rank",
  l."category",
  l."categoryKey",
  b."prevRank",
  b."prevCapturedAt",
  CASE WHEN b."prevRank" IS NOT NULL THEN l."rank" - b."prevRank" END AS "rankDelta",
  CASE
    WHEN b."prevRank" IS NOT NULL AND b."prevRank" > 0
      THEN round(((l."rank" - b."prevRank")::numeric / b."prevRank") * 100, 2)
  END AS "rankDeltaPercent"
FROM latest l
LEFT JOIN baseline b
  ON b."storeKey" = l."storeKey"
 AND b."asin" = l."asin"
WHERE (
  l."sku" IS NULL
  OR length(trim(l."sku")) = 0
  OR NOT EXISTS (
    SELECT 1 FROM product."ListingIgnoredSku" i
    WHERE lower(i.sku) = lower(l."sku")
  )
)
AND NOT (
  EXISTS (
    SELECT 1 FROM product."StoreListingContentSnapshot" s
    WHERE upper(btrim(s.asin)) = upper(btrim(l.asin))
      AND s."storeKey" = l."storeKey"
      AND length(trim(s.sku)) > 0
  )
  AND NOT EXISTS (
    SELECT 1 FROM product."StoreListingContentSnapshot" s
    WHERE upper(btrim(s.asin)) = upper(btrim(l.asin))
      AND s."storeKey" = l."storeKey"
      AND length(trim(s.sku)) > 0
      AND NOT EXISTS (
        SELECT 1 FROM product."ListingIgnoredSku" i
        WHERE lower(i.sku) = lower(s.sku)
      )
  )
);

CREATE VIEW "product"."v_listing_review_alert"
WITH (security_invoker = true) AS
WITH latest_content_by_sku AS (
  SELECT DISTINCT ON ("channel", "storeKey", "sku")
    "channel",
    "storeKey",
    "sku",
    "inventoryProductId",
    "inventoryProductName",
    "title",
    "asin"
  FROM "product"."StoreListingContentSnapshot"
  WHERE "sku" IS NOT NULL AND length(trim("sku")) > 0
    AND NOT EXISTS (
      SELECT 1 FROM product."ListingIgnoredSku" i
      WHERE lower(i.sku) = lower("StoreListingContentSnapshot"."sku")
    )
  ORDER BY "channel", "storeKey", "sku", "capturedAt" DESC
),
latest_content_by_asin AS (
  SELECT DISTINCT ON ("channel", upper("asin"))
    "channel",
    upper("asin") AS asin_key,
    "storeKey",
    "sku",
    "inventoryProductId",
    "inventoryProductName",
    "title"
  FROM "product"."StoreListingContentSnapshot"
  WHERE "asin" IS NOT NULL AND length(trim("asin")) > 0
    AND NOT EXISTS (
      SELECT 1 FROM product."ListingIgnoredSku" i
      WHERE lower(i.sku) = lower("StoreListingContentSnapshot"."sku")
    )
  ORDER BY "channel", upper("asin"), "capturedAt" DESC
)
SELECT
  r."id",
  r."channel",
  COALESCE(cs."storeKey", ca."storeKey", r."storeKey") AS "storeKey",
  r."countryCode",
  r."asin",
  COALESCE(NULLIF(r."sku", ''), cs."sku", ca."sku") AS "sku",
  r."externalId",
  r."rating",
  r."title" AS "reviewTitle",
  r."body" AS "reviewBody",
  r."author",
  r."viewed",
  r."verified",
  r."reviewedAt",
  r."capturedAt",
  COALESCE(cs."inventoryProductId", ca."inventoryProductId") AS "inventoryProductId",
  COALESCE(cs."inventoryProductName", ca."inventoryProductName") AS "inventoryProductName",
  COALESCE(NULLIF(cs."title", ''), NULLIF(ca."title", ''), r."title") AS "listingTitle"
FROM "product"."StoreCustomerReview" r
LEFT JOIN latest_content_by_sku cs
  ON cs."channel" = r."channel"
 AND cs."storeKey" = r."storeKey"
 AND r."sku" IS NOT NULL
 AND length(trim(r."sku")) > 0
 AND cs."sku" = r."sku"
LEFT JOIN latest_content_by_asin ca
  ON ca."channel" = r."channel"
 AND ca.asin_key = upper(r."asin")
WHERE r."rating" <= 3
  AND COALESCE(r."reviewedAt", r."capturedAt"::date) >= (CURRENT_DATE - 180)
  AND NOT EXISTS (
    SELECT 1 FROM product."ListingIgnoredSku" i
    WHERE lower(i.sku) = lower(COALESCE(NULLIF(r."sku", ''), cs."sku", ca."sku"))
  );

CREATE MATERIALIZED VIEW "product"."mv_listing_health_current" AS
SELECT * FROM "product"."v_listing_health_current"
WITH NO DATA;

CREATE UNIQUE INDEX "mv_listing_health_current_id_uidx"
  ON "product"."mv_listing_health_current" ("id");

CREATE INDEX "mv_listing_health_current_store_idx"
  ON "product"."mv_listing_health_current" ("channel", "storeKey");

CREATE INDEX "mv_listing_health_current_asin_idx"
  ON "product"."mv_listing_health_current" ("storeKey", "asin");

CREATE INDEX "mv_listing_health_current_inactive_idx"
  ON "product"."mv_listing_health_current" ("channel", "storeKey")
  WHERE "inactivityReason" IS NOT NULL;

CREATE INDEX "mv_listing_health_current_score_idx"
  ON "product"."mv_listing_health_current" ("channel", "storeKey", "listingScore")
  WHERE "listingScore" IS NOT NULL;

CREATE MATERIALIZED VIEW "product"."mv_listing_sales_returns_30d" AS
SELECT * FROM "product"."v_listing_sales_returns_30d"
WITH NO DATA;

CREATE UNIQUE INDEX "mv_listing_sales_returns_30d_id_uidx"
  ON "product"."mv_listing_sales_returns_30d" ("id");

CREATE INDEX "mv_listing_sales_returns_30d_store_sku_idx"
  ON "product"."mv_listing_sales_returns_30d" ("channel", "storeKey", "sku");

CREATE INDEX "mv_listing_sales_returns_30d_alert_idx"
  ON "product"."mv_listing_sales_returns_30d" ("channel", "storeKey")
  WHERE "units30" >= 5 AND "returnRate30" > 10;

CREATE MATERIALIZED VIEW "product"."mv_listing_bsr_trend" AS
SELECT * FROM "product"."v_listing_bsr_trend"
WITH NO DATA;

CREATE UNIQUE INDEX "mv_listing_bsr_trend_id_uidx"
  ON "product"."mv_listing_bsr_trend" ("id");

CREATE INDEX "mv_listing_bsr_trend_store_asin_idx"
  ON "product"."mv_listing_bsr_trend" ("storeKey", "asin");

CREATE INDEX "mv_listing_bsr_trend_down_idx"
  ON "product"."mv_listing_bsr_trend" ("storeKey")
  WHERE "rankDeltaPercent" IS NOT NULL AND "rankDeltaPercent" > 20;

CREATE MATERIALIZED VIEW "product"."mv_listing_review_alert" AS
SELECT * FROM "product"."v_listing_review_alert"
WITH NO DATA;

CREATE UNIQUE INDEX "mv_listing_review_alert_id_uidx"
  ON "product"."mv_listing_review_alert" ("id");

CREATE INDEX "mv_listing_review_alert_store_idx"
  ON "product"."mv_listing_review_alert" ("channel", "storeKey");

CREATE INDEX "mv_listing_review_alert_day_idx"
  ON "product"."mv_listing_review_alert" ("channel", "storeKey", "reviewedAt", "capturedAt");

CREATE MATERIALIZED VIEW "product"."mv_listing_health_store_stats" AS
WITH health AS (
  SELECT
    h."storeKey",
    h."channel",
    MAX(h."countryCode") AS "countryCode",
    COUNT(*)::int AS monitored,
    COUNT(*) FILTER (WHERE h."inactivityReason" IS NOT NULL)::int AS inactive,
    AVG(h."listingScore") AS "avgScore",
    COUNT(*) FILTER (
      WHERE h."listingScore" IS NOT NULL AND h."listingScore" < 6
    )::int AS "lowScore"
  FROM "product"."mv_listing_health_current" h
  GROUP BY h."storeKey", h."channel"
),
sales AS (
  SELECT
    s."storeKey",
    s."channel",
    SUM(s."units30")::int AS units30,
    SUM(s."returns30")::int AS returns30,
    SUM(s."unitsPrev30")::int AS "unitsPrev30",
    SUM(s."returnsPrev30")::int AS "returnsPrev30",
    COUNT(*) FILTER (
      WHERE s."units30" >= 5 AND s."returnRate30" > 10
    )::int AS "returnsAlert"
  FROM "product"."mv_listing_sales_returns_30d" s
  GROUP BY s."storeKey", s."channel"
),
bsr AS (
  SELECT
    b."storeKey",
    b."channel",
    COUNT(*) FILTER (
      WHERE b."rankDeltaPercent" IS NOT NULL AND b."rankDeltaPercent" > 20
    )::int AS "bsrDown"
  FROM "product"."mv_listing_bsr_trend" b
  GROUP BY b."storeKey", b."channel"
),
reviews AS (
  SELECT
    r."storeKey",
    r."channel",
    COUNT(*) FILTER (WHERE r.d >= CURRENT_DATE - 30)::int AS reviews30,
    COUNT(*) FILTER (
      WHERE r.d >= CURRENT_DATE - 60 AND r.d < CURRENT_DATE - 30
    )::int AS "reviewsPrev30",
    COUNT(*) FILTER (WHERE r.d >= CURRENT_DATE - 90)::int AS reviews90,
    COUNT(*) FILTER (
      WHERE r.d >= CURRENT_DATE - 180 AND r.d < CURRENT_DATE - 90
    )::int AS "reviewsPrev90",
    COUNT(*) FILTER (WHERE r.d >= CURRENT_DATE - 365)::int AS reviews365,
    COUNT(*) FILTER (
      WHERE r.d >= CURRENT_DATE - 730 AND r.d < CURRENT_DATE - 365
    )::int AS "reviewsPrev365"
  FROM (
    SELECT
      "storeKey",
      "channel",
      COALESCE("reviewedAt", "capturedAt"::date) AS d
    FROM "product"."mv_listing_review_alert"
  ) r
  GROUP BY r."storeKey", r."channel"
)
SELECT
  COALESCE(h."storeKey", s."storeKey", b."storeKey", r."storeKey") AS "storeKey",
  COALESCE(h."channel", s."channel", b."channel", r."channel") AS "channel",
  COALESCE(h."countryCode", '') AS "countryCode",
  COALESCE(h.monitored, 0) AS monitored,
  COALESCE(h.inactive, 0) AS inactive,
  h."avgScore",
  COALESCE(h."lowScore", 0) AS "lowScore",
  COALESCE(s.units30, 0) AS units30,
  COALESCE(s.returns30, 0) AS returns30,
  COALESCE(s."unitsPrev30", 0) AS "unitsPrev30",
  COALESCE(s."returnsPrev30", 0) AS "returnsPrev30",
  COALESCE(s."returnsAlert", 0) AS "returnsAlert",
  COALESCE(b."bsrDown", 0) AS "bsrDown",
  COALESCE(r.reviews30, 0) AS reviews30,
  COALESCE(r."reviewsPrev30", 0) AS "reviewsPrev30",
  COALESCE(r.reviews90, 0) AS reviews90,
  COALESCE(r."reviewsPrev90", 0) AS "reviewsPrev90",
  COALESCE(r.reviews365, 0) AS reviews365,
  COALESCE(r."reviewsPrev365", 0) AS "reviewsPrev365"
FROM health h
FULL JOIN sales s
  ON s."storeKey" = h."storeKey"
 AND s."channel" = h."channel"
FULL JOIN bsr b
  ON b."storeKey" = COALESCE(h."storeKey", s."storeKey")
 AND b."channel" = COALESCE(h."channel", s."channel")
FULL JOIN reviews r
  ON r."storeKey" = COALESCE(h."storeKey", s."storeKey", b."storeKey")
 AND r."channel" = COALESCE(h."channel", s."channel", b."channel")
WITH NO DATA;

CREATE UNIQUE INDEX "mv_listing_health_store_stats_pk"
  ON "product"."mv_listing_health_store_stats" ("channel", "storeKey");
