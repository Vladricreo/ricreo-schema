-- Dashboard salute listing: view di lettura su snapshot già popolati dai cron.
-- Non materializzate: security_invoker così restano nel grant del ruolo applicativo.

DROP VIEW IF EXISTS "product"."v_listing_review_alert";
DROP VIEW IF EXISTS "product"."v_listing_bsr_trend";
DROP VIEW IF EXISTS "product"."v_listing_sales_returns_30d";
DROP VIEW IF EXISTS "product"."v_listing_health_current";

-- Stato corrente di ogni listing (ultimo contenuto + attività + inattività aperta).
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

-- Vendite e resi 30 giorni vs 30 giorni precedenti, per SKU × store.
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

-- Trend BSR Amazon: rank primario corrente vs baseline (~7 giorni, primo snapshot).
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
 AND b."asin" = l."asin";

-- Recensioni ≤3★ ultimi 180 giorni, con id interno (task) e externalId (presa visione).
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
  AND COALESCE(r."reviewedAt", r."capturedAt"::date) >= (CURRENT_DATE - 180);
