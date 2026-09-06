-- Default spedizione FBM per paese + media da inventory.Shipment / ShipmentLine.
-- Solo schema product. La view legge inventory in sola lettura.

CREATE TABLE IF NOT EXISTS "product"."ShippingPrice" (
    "countryCode" VARCHAR(2) NOT NULL,
    "amount" DECIMAL(12,2) NOT NULL,
    "currency" VARCHAR(3) NOT NULL DEFAULT 'EUR',
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ShippingPrice_pkey" PRIMARY KEY ("countryCode")
);

CREATE OR REPLACE VIEW "product"."v_country_shipping_cost"
WITH (security_invoker = true) AS
WITH fbm_shipments AS (
  SELECT
    CASE
      WHEN length(btrim(s."recipientCountry")) = 2 THEN
        CASE UPPER(btrim(s."recipientCountry"))
          WHEN 'UK' THEN 'GB'
          WHEN 'EL' THEN 'GR'
          WHEN 'XI' THEN 'GB'
          ELSE UPPER(btrim(s."recipientCountry"))
        END
      ELSE NULL
    END AS country_code,
    COALESCE(s."shippedAt", s."orderedAt") AS ship_at,
    (s."shippingCost" / NULLIF(qty.total_qty, 0)::numeric) AS unit_cost
  FROM inventory."Shipment" s
  INNER JOIN LATERAL (
    SELECT COALESCE(SUM(GREATEST(l.quantity, 0)), 0) AS total_qty
    FROM inventory."ShipmentLine" l
    WHERE l."shipmentId" = s.id
  ) qty ON TRUE
  WHERE s."shipmentType" IS DISTINCT FROM 'FBA'
    AND s."shippingCost" IS NOT NULL
    AND s."shippingCost" > 0
    AND qty.total_qty > 0
    AND COALESCE(s."shippedAt", s."orderedAt") > TIMESTAMPTZ '1971-01-01'
    AND s."recipientCountry" IS NOT NULL
    AND btrim(s."recipientCountry") <> ''
),
valid AS (
  SELECT *
  FROM fbm_shipments
  WHERE country_code IS NOT NULL
    AND length(country_code) = 2
),
country_meta AS (
  SELECT
    country_code,
    MIN(ship_at) AS first_at,
    BOOL_OR(ship_at >= NOW() - INTERVAL '30 days') AS has_recent
  FROM valid
  GROUP BY country_code
),
windowed AS (
  SELECT
    v.country_code,
    v.ship_at,
    v.unit_cost,
    m.first_at,
    (
      m.first_at <= NOW() - INTERVAL '30 days'
      AND m.has_recent
    ) AS use_30d
  FROM valid v
  JOIN country_meta m ON m.country_code = v.country_code
  WHERE
    CASE
      WHEN m.first_at <= NOW() - INTERVAL '30 days' AND m.has_recent
        THEN v.ship_at >= NOW() - INTERVAL '30 days'
      ELSE TRUE
    END
)
SELECT
  w.country_code,
  ROUND(AVG(w.unit_cost)::numeric, 2) AS unit_cost,
  COUNT(*)::int AS shipment_count,
  CASE
    WHEN BOOL_OR(w.use_30d) THEN 30
    ELSE GREATEST(
      1,
      CEIL(EXTRACT(EPOCH FROM (NOW() - MIN(w.first_at))) / 86400.0)::int
    )
  END AS window_days,
  (NOT BOOL_OR(w.use_30d)) AS used_latest_fallback,
  MIN(w.ship_at) AS sample_from,
  MAX(w.ship_at) AS sample_to
FROM windowed w
GROUP BY w.country_code;

INSERT INTO "product"."ShippingPrice" (
    "countryCode",
    "amount",
    "currency",
    "createdAt",
    "updatedAt"
)
SELECT
    v.country_code,
    v.unit_cost,
    'EUR',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
FROM "product"."v_country_shipping_cost" v
ON CONFLICT ("countryCode") DO NOTHING;
