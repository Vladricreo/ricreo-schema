-- eBay: ogni inserzione resta un prodotto (identityKey = item ID), così un
-- seller può avere più listing dello stesso articolo e collegarli via match.
-- Amazon non viene toccato (ASIN/EAN restano la chiave).
-- Solo schema product.
--
-- Sicuro da rieseguire: aggiorna solo le righe eBay la cui identityKey non è
-- già `item:…` e non collide con un'altra riga dello stesso canale.

WITH ebay_products AS (
    SELECT p."id", p."competitorChannelId"
    FROM "product"."CompetitorProduct" p
    JOIN "product"."CompetitorChannel" c ON c."id" = p."competitorChannelId"
    WHERE c."channel" = 'EBAY'
      AND p."identityKey" NOT LIKE 'item:%'
),
picked_offer AS (
    SELECT DISTINCT ON (o."productId")
        o."productId",
        upper(trim(BOTH FROM
            CASE
                WHEN o."externalItemId" LIKE 'v1|%' THEN split_part(o."externalItemId", '|', 2)
                ELSE o."externalItemId"
            END
        )) AS item_id
    FROM "product"."CompetitorListingOffer" o
    JOIN ebay_products p ON p."id" = o."productId"
    WHERE o."externalItemId" IS NOT NULL
      AND trim(BOTH FROM o."externalItemId") <> ''
    ORDER BY
        o."productId",
        CASE WHEN o."countryCode" = 'IT' THEN 0 ELSE 1 END,
        CASE WHEN o."status" = 'ACTIVE' THEN 0 ELSE 1 END,
        o."countryCode"
),
candidates AS (
    SELECT
        p."id",
        p."competitorChannelId",
        'item:' || o.item_id AS new_key
    FROM ebay_products p
    JOIN picked_offer o ON o."productId" = p."id"
    WHERE o.item_id <> ''
)
UPDATE "product"."CompetitorProduct" p
SET
    "identityKey" = c.new_key,
    "updatedAt" = CURRENT_TIMESTAMP
FROM candidates c
WHERE p."id" = c."id"
  AND NOT EXISTS (
      SELECT 1
      FROM "product"."CompetitorProduct" other
      WHERE other."competitorChannelId" = c."competitorChannelId"
        AND other."identityKey" = c.new_key
        AND other."id" <> c."id"
  );
