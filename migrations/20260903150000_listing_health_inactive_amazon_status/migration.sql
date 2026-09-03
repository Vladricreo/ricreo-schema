-- Allinea il motivo di inattività della dashboard salute allo stato Amazon
-- (BUYABLE / DISCOVERABLE), come il filtro "Non acquistabili" in
-- /dashboard/listings/amazon. Prima si etichettava OUT_OF_STOCK appena la
-- quantità era 0, anche se Amazon aveva già tolto BUYABLE/DISCOVERABLE.

CREATE OR REPLACE VIEW "product"."v_listing_health_current"
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
  CASE
    WHEN a."isBuyable" IS TRUE THEN NULL
    WHEN a."isBuyable" IS FALSE THEN
      CASE
        WHEN COALESCE(a."isPublished", false) IS NOT TRUE THEN 'ABSENT'
        WHEN COALESCE(a."isDiscoverable", false) IS NOT TRUE THEN 'NOT_DISCOVERABLE'
        WHEN a.quantity IS NOT DISTINCT FROM 0 THEN 'OUT_OF_STOCK'
        ELSE 'NOT_BUYABLE'
      END
    ELSE i."inactivityReason"
  END AS "inactivityReason",
  CASE
    WHEN a."isBuyable" IS TRUE THEN NULL
    WHEN a."isBuyable" IS FALSE THEN COALESCE(i."inactivityStartedAt", a."activityCapturedAt")
    ELSE i."inactivityStartedAt"
  END AS "inactivityStartedAt",
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

-- Riallinea i periodi aperti già salvati alla nuova precedenza (stato Amazon prima della qty).
UPDATE product."StoreListingInactivityPeriod" p
SET
  reason = CASE
    WHEN a."isPublished" IS NOT TRUE THEN 'ABSENT'
    WHEN a."isDiscoverable" IS NOT TRUE THEN 'NOT_DISCOVERABLE'
    WHEN a.quantity IS NOT DISTINCT FROM 0 THEN 'OUT_OF_STOCK'
    ELSE 'NOT_BUYABLE'
  END,
  "updatedAt" = CURRENT_TIMESTAMP
FROM (
  SELECT DISTINCT ON ("channel", "storeKey", "sku")
    "channel",
    "storeKey",
    "sku",
    "isPublished",
    "isDiscoverable",
    quantity,
    "isBuyable"
  FROM product."StoreListingActivitySnapshot"
  ORDER BY "channel", "storeKey", "sku", "capturedAt" DESC
) a
WHERE p."endedAt" IS NULL
  AND p."channel" = a."channel"
  AND p."storeKey" = a."storeKey"
  AND p.sku = a.sku
  AND a."isBuyable" IS FALSE
  AND p.reason IS DISTINCT FROM CASE
    WHEN a."isPublished" IS NOT TRUE THEN 'ABSENT'
    WHEN a."isDiscoverable" IS NOT TRUE THEN 'NOT_DISCOVERABLE'
    WHEN a.quantity IS NOT DISTINCT FROM 0 THEN 'OUT_OF_STOCK'
    ELSE 'NOT_BUYABLE'
  END;
