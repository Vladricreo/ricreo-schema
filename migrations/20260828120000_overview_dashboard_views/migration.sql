-- ============================================================================
-- Overview dashboard: P&L per riga ordine, poi matview giorno×canale / SKU.
-- Calcolo allineato a sales-analytics (fee Finances → listing → Fee Preview,
-- FBM da etichetta / ShippingPrice / media paese, COGS da pricing summary).
-- Applicabile anche via psql / Supabase CLI. Se lo fai fuori da Prisma:
--   bunx prisma migrate resolve --applied 20260828120000_overview_dashboard_views
-- ============================================================================

DROP MATERIALIZED VIEW IF EXISTS "product"."mv_overview_sku_daily";
DROP MATERIALIZED VIEW IF EXISTS "product"."mv_overview_sales_daily";
DROP VIEW IF EXISTS "product"."v_order_line_refund";
DROP VIEW IF EXISTS "product"."v_order_line_pnl";
DROP MATERIALIZED VIEW IF EXISTS "product"."mv_overview_sku_meta";
DROP FUNCTION IF EXISTS "product".iso_country(text);

-- Normalizza un codice paese in ISO-2 (UK/EL/XI come in fbm-cost-sql.ts).
CREATE FUNCTION "product".iso_country(raw text)
RETURNS varchar(2)
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT CASE
    WHEN raw IS NULL OR btrim(raw) = '' THEN NULL
    WHEN length(btrim(raw)) = 2 THEN
      CASE UPPER(btrim(raw))
        WHEN 'UK' THEN 'GB'
        WHEN 'EL' THEN 'GR'
        WHEN 'XI' THEN 'GB'
        ELSE UPPER(btrim(raw))
      END
    ELSE NULL
  END
$$;

-- Costo unitario e anagrafica SKU (pricing summary è pesante: una riga per SKU).
CREATE MATERIALIZED VIEW "product"."mv_overview_sku_meta" AS
SELECT DISTINCT ON (inv_sku.code)
  inv_sku.code AS sku,
  COALESCE(NULLIF(pricing.total_cost, 0), NULLIF(inv_p.cost, 0)) AS unit_cost_eur,
  inv_p.name AS product_name,
  inv_p."imageUrl" AS image_url,
  COALESCE(inv_sku.asin, inv_p.asin) AS asin
FROM inventory."Sku" inv_sku
JOIN inventory."Product" inv_p ON inv_p.id = inv_sku."productId"
LEFT JOIN inventory_views.v_product_pricing_summary pricing ON pricing.product_id = inv_p.id
ORDER BY inv_sku.code, inv_sku."isDefault" DESC, inv_sku."updatedAt" DESC;

CREATE UNIQUE INDEX "mv_overview_sku_meta_sku_uidx"
  ON "product"."mv_overview_sku_meta" (sku);

-- P&L di ogni riga StoreOrderLine, importi in EUR.
CREATE VIEW "product"."v_order_line_pnl"
WITH (security_invoker = true) AS
SELECT
  line.channel,
  line.store_key,
  line.amazon_order_id,
  line.purchase_day,
  line.sku,
  COALESCE(meta.asin, line.asin) AS asin,
  COALESCE(meta.product_name, line.product_name) AS product_name,
  line.dest_country AS ship_country,
  CASE
    WHEN line.is_fba THEN 'FBA'
    WHEN line.is_fbm THEN 'FBM'
    ELSE COALESCE(NULLIF(btrim(line.fulfillment_channel), ''), 'FBM')
  END AS fulfillment,
  line.is_sold,
  line.quantity,
  CASE WHEN line.is_sold THEN ROUND(line.gross_local * line.eur_factor, 4) ELSE 0 END AS gross_eur,
  CASE WHEN line.is_sold THEN ROUND(line.vat_local * line.eur_factor, 4) ELSE 0 END AS vat_eur,
  CASE WHEN line.is_sold THEN ROUND(line.referral_local * line.eur_factor, 4) ELSE 0 END AS referral_eur,
  CASE WHEN line.is_sold THEN ROUND(line.digital_local * line.eur_factor, 4) ELSE 0 END AS digital_eur,
  CASE WHEN line.is_sold THEN ROUND(line.fba_fee_local * line.eur_factor, 4) ELSE 0 END AS fba_fee_eur,
  CASE WHEN line.is_sold THEN ROUND(line.chargeback_local * line.eur_factor, 4) ELSE 0 END AS chargeback_eur,
  CASE WHEN line.is_sold THEN ROUND(line.other_fee_local * line.eur_factor, 4) ELSE 0 END AS other_fee_eur,
  CASE WHEN line.is_sold THEN ROUND(line.refund_commission_local * line.eur_factor, 4) ELSE 0 END AS refund_commission_eur,
  CASE WHEN line.is_sold THEN ROUND(line.fbm_shipping_eur, 4) ELSE 0 END AS fbm_shipping_eur,
  meta.unit_cost_eur,
  CASE
    WHEN line.is_sold AND meta.unit_cost_eur IS NOT NULL
      THEN ROUND(meta.unit_cost_eur * GREATEST(line.quantity, 0), 4)
    ELSE 0
  END AS cogs_eur,
  line.has_fee_estimate
FROM (
  SELECT
    o.channel::text AS channel,
    o."storeKey" AS store_key,
    o."amazonOrderId" AS amazon_order_id,
    (o."purchaseDate")::date AS purchase_day,
    o.sku,
    o.asin,
    o."productName" AS product_name,
    GREATEST(o.quantity, 0) AS quantity,
    o."fulfillmentChannel" AS fulfillment_channel,
    (
      o."itemStatus" IS NULL
      OR btrim(o."itemStatus") = ''
      OR o."itemStatus" = 'Shipped'
    ) AS is_sold,
    (o."fulfillmentChannel" = 'FBA') AS is_fba,
    (
      o."fulfillmentChannel" = 'FBM'
      OR (
        o.channel::text IS DISTINCT FROM 'AMAZON'
        AND (o."fulfillmentChannel" IS NULL OR btrim(o."fulfillmentChannel") = '')
      )
    ) AS is_fbm,
    COALESCE(
      "product".iso_country(inv_ship.recipient_country),
      "product".iso_country(o."shipCountry"),
      NULLIF(btrim(o."shipCountry"), '')
    ) AS dest_country,
    (
      COALESCE(o."itemPrice", 0)
      - COALESCE(o."itemPromotionDiscount", 0)
      + COALESCE(o."shippingPrice", 0)
      - COALESCE(o."shipPromotionDiscount", 0)
    ) AS gross_local,
    (COALESCE(o."itemTax", 0) + COALESCE(o."shippingTax", 0)) AS vat_local,
    CASE
      WHEN o.currency IS NULL
        OR btrim(o.currency) = ''
        OR UPPER(btrim(o.currency)) = 'EUR'
        OR fx.rate IS NULL
        OR fx.rate <= 0
      THEN 1::numeric
      ELSE 1 / fx.rate
    END AS eur_factor,
    CASE
      WHEN o.channel = 'AMAZON' THEN
        COALESCE(
          NULLIF(fee."referralFee", 0),
          CASE
            WHEN COALESCE(listing."listingReferralFee", 0) > 0 THEN
              ROUND(
                listing."listingReferralFee" * (
                  CASE
                    WHEN (COALESCE(listing."listingPrice", 0) + COALESCE(listing."listingCustomerShipping", 0)) > 0
                      AND (
                        COALESCE(o."itemPrice", 0)
                        - COALESCE(o."itemPromotionDiscount", 0)
                        + COALESCE(o."shippingPrice", 0)
                        - COALESCE(o."shipPromotionDiscount", 0)
                      ) > 0
                    THEN (
                      COALESCE(o."itemPrice", 0)
                      - COALESCE(o."itemPromotionDiscount", 0)
                      + COALESCE(o."shippingPrice", 0)
                      - COALESCE(o."shipPromotionDiscount", 0)
                    ) / (COALESCE(listing."listingPrice", 0) + COALESCE(listing."listingCustomerShipping", 0))
                    ELSE GREATEST(o.quantity, 1)::numeric
                  END
                ),
                4
              )
            ELSE NULL
          END,
          NULLIF(f."referralFeePerUnit", 0) * GREATEST(o.quantity, 0),
          0
        )
      ELSE
        (
          COALESCE(o."itemPrice", 0)
          - COALESCE(o."itemPromotionDiscount", 0)
          + COALESCE(o."shippingPrice", 0)
          - COALESCE(o."shipPromotionDiscount", 0)
        ) * (
          CASE o.channel
            WHEN 'EBAY' THEN COALESCE(sale_fees."ebayPercent", 12.8)
            WHEN 'ETSY' THEN COALESCE(sale_fees."etsyPercent", 10.5)
            WHEN 'TEMU' THEN COALESCE(sale_fees."temuPercent", 15)
            ELSE 0
          END
        ) / 100
        + (
          CASE o.channel
            WHEN 'EBAY' THEN COALESCE(sale_fees."ebayFixedEur", 0.35)
            WHEN 'ETSY' THEN COALESCE(sale_fees."etsyFixedEur", 0.30)
            WHEN 'TEMU' THEN COALESCE(sale_fees."temuFixedEur", 0)
            ELSE 0
          END
        ) / NULLIF(
          CASE
            WHEN o.currency IS NULL
              OR btrim(o.currency) = ''
              OR UPPER(btrim(o.currency)) = 'EUR'
              OR fx.rate IS NULL
              OR fx.rate <= 0
            THEN 1::numeric
            ELSE 1 / fx.rate
          END,
          0
        )
    END AS referral_local,
    CASE
      WHEN o.channel IS DISTINCT FROM 'AMAZON' THEN 0
      ELSE COALESCE(
        NULLIF(fee."digitalServicesFee", 0),
        CASE
          WHEN COALESCE(listing."listingDigitalFee", 0) > 0 THEN
            ROUND(
              listing."listingDigitalFee" * (
                CASE
                  WHEN (COALESCE(listing."listingPrice", 0) + COALESCE(listing."listingCustomerShipping", 0)) > 0
                    AND (
                      COALESCE(o."itemPrice", 0)
                      - COALESCE(o."itemPromotionDiscount", 0)
                      + COALESCE(o."shippingPrice", 0)
                      - COALESCE(o."shipPromotionDiscount", 0)
                    ) > 0
                  THEN (
                    COALESCE(o."itemPrice", 0)
                    - COALESCE(o."itemPromotionDiscount", 0)
                    + COALESCE(o."shippingPrice", 0)
                    - COALESCE(o."shipPromotionDiscount", 0)
                  ) / (COALESCE(listing."listingPrice", 0) + COALESCE(listing."listingCustomerShipping", 0))
                  ELSE GREATEST(o.quantity, 1)::numeric
                END
              ),
              4
            )
          ELSE NULL
        END,
        0
      )
    END AS digital_local,
    CASE
      WHEN o."fulfillmentChannel" = 'FBA' THEN
        COALESCE(
          NULLIF(fee."fbaFulfillmentFee", 0),
          COALESCE(
            NULLIF((f."fbaFeeByCountry" ->> "product".iso_country(o."shipCountry"))::numeric, 0),
            NULLIF(f."fbaFeeDomestic", 0)
          ) * GREATEST(o.quantity, 0),
          NULLIF(listing."listingFbaFee", 0) * GREATEST(o.quantity, 0),
          0
        )
      ELSE 0
    END AS fba_fee_local,
    COALESCE(
      NULLIF(fee."shippingChargeback", 0),
      CASE
        WHEN o."fulfillmentChannel" = 'FBA' THEN COALESCE(o."shippingPrice", 0) / 1.22
        ELSE 0
      END
    ) AS chargeback_local,
    COALESCE(NULLIF(fee."otherFee", 0), 0) AS other_fee_local,
    COALESCE(NULLIF(fee."refundCommission", 0), 0) AS refund_commission_local,
    CASE
      WHEN o."fulfillmentChannel" = 'FBA' THEN 0
      WHEN NOT (
        o."fulfillmentChannel" = 'FBM'
        OR (
          o.channel::text IS DISTINCT FROM 'AMAZON'
          AND (o."fulfillmentChannel" IS NULL OR btrim(o."fulfillmentChannel") = '')
        )
      ) THEN 0
      WHEN inv_ship.unit_cost IS NOT NULL THEN inv_ship.unit_cost * GREATEST(o.quantity, 0)
      ELSE COALESCE(def_ship.amount, avg_ship.unit_cost, 0)
    END AS fbm_shipping_eur,
    CASE
      WHEN o.channel = 'AMAZON' THEN
        (
          COALESCE(fee."referralFee", 0) > 0
          OR COALESCE(fee."fbaFulfillmentFee", 0) > 0
          OR COALESCE(fee."otherFee", 0) > 0
          OR COALESCE(fee."digitalServicesFee", 0) > 0
          OR COALESCE(f."referralFeePerUnit", 0) > 0
          OR COALESCE(listing."listingReferralFee", 0) > 0
          OR COALESCE(listing."listingFbaFee", 0) > 0
        )
      ELSE TRUE
    END AS has_fee_estimate
  FROM product."StoreOrderLine" o
  LEFT JOIN LATERAL (
    SELECT
      f."referralFeePerUnit",
      f."fbaFeeDomestic",
      f."fbaFeeByCountry"
    FROM product."StoreSkuFeeEstimate" f
    WHERE f.channel = 'AMAZON'
      AND f.sku = o.sku
    ORDER BY
      CASE
        WHEN f."storeKey" = o."storeKey" THEN 0
        WHEN f."storeKey" = 'APJ6JRA9NG5V4' THEN 1
        ELSE 2
      END,
      f."updatedAt" DESC
    LIMIT 1
  ) f ON TRUE
  LEFT JOIN LATERAL (
    SELECT
      e."referralFee" AS "listingReferralFee",
      e."digitalServicesFee" AS "listingDigitalFee",
      e."fbaFee" AS "listingFbaFee",
      e."listingPrice" AS "listingPrice",
      e."customerShipping" AS "listingCustomerShipping"
    FROM product."ListingProfitEstimate" e
    WHERE e.channel = 'AMAZON'
      AND o.channel = 'AMAZON'
      AND e.sku = o.sku
    ORDER BY
      CASE
        WHEN e."storeKey" = o."storeKey" THEN 0
        WHEN "product".iso_country(o."shipCountry") IS NOT NULL
          AND e."countryCode" = "product".iso_country(o."shipCountry") THEN 1
        WHEN e."storeKey" = 'APJ6JRA9NG5V4' THEN 2
        ELSE 3
      END,
      e."importedAt" DESC
    LIMIT 1
  ) listing ON TRUE
  LEFT JOIN LATERAL (
    SELECT
      sf."fbaFulfillmentFee",
      sf."referralFee",
      sf."digitalServicesFee",
      sf."shippingChargeback",
      sf."refundCommission",
      sf."otherFee"
    FROM product."StoreOrderFee" sf
    WHERE sf.channel = o.channel
      AND sf."amazonOrderId" = o."amazonOrderId"
      AND (
        (sf."orderItemId" <> '' AND sf."orderItemId" = COALESCE(o."orderItemId", ''))
        OR sf.sku = o.sku
      )
    ORDER BY
      CASE WHEN sf."postedDate" IS NOT NULL THEN 0 ELSE 1 END,
      CASE
        WHEN sf."orderItemId" <> '' AND sf."orderItemId" = COALESCE(o."orderItemId", '') THEN 0
        ELSE 1
      END,
      CASE WHEN sf.sku = o.sku THEN 0 ELSE 1 END
    LIMIT 1
  ) fee ON TRUE
  LEFT JOIN LATERAL (
    SELECT
      CASE
        WHEN s."shippingCost" IS NOT NULL AND s."shippingCost" > 0 AND qty.total_qty > 0
          THEN s."shippingCost" / qty.total_qty
        ELSE NULL
      END AS unit_cost,
      s."recipientCountry" AS recipient_country
    FROM inventory."Shipment" s
    INNER JOIN LATERAL (
      SELECT COALESCE(SUM(GREATEST(l.quantity, 0)), 0) AS total_qty
      FROM inventory."ShipmentLine" l
      WHERE l."shipmentId" = s.id
    ) qty ON TRUE
    WHERE o."amazonOrderId" IS NOT NULL
      AND btrim(o."amazonOrderId") <> ''
      AND s."shipmentType" IS DISTINCT FROM 'FBA'
      AND (
        s."marketplaceOrderId" = o."amazonOrderId"
        OR s."marketplaceOrderId" = o."orderItemId"
        OR (
          o.channel = 'TEMU'
          AND s."marketplaceOrderId" = CONCAT(
            'PO-',
            regexp_replace(o."amazonOrderId", '^PO-', '', 'i')
          )
        )
        OR (
          o.channel = 'TEMU'
          AND o."orderItemId" IS NOT NULL
          AND s."marketplaceOrderId" = CONCAT(
            'PO-',
            regexp_replace(o."orderItemId", '^PO-', '', 'i')
          )
        )
      )
    ORDER BY
      EXISTS (
        SELECT 1
        FROM inventory."ShipmentLine" sl
        LEFT JOIN inventory."Sku" sku ON sku.id = sl."skuId"
        WHERE sl."shipmentId" = s.id
          AND COALESCE(sl."skuCodeSnapshot", sku.code) = o.sku
      ) DESC,
      COALESCE(s."shippedAt", s."orderedAt") DESC NULLS LAST
    LIMIT 1
  ) inv_ship ON TRUE
  LEFT JOIN product."ShippingPrice" def_ship
    ON def_ship."countryCode" = COALESCE(
      "product".iso_country(inv_ship.recipient_country),
      "product".iso_country(o."shipCountry"),
      NULLIF(btrim(o."shipCountry"), '')
    )
  LEFT JOIN product.v_country_shipping_cost avg_ship
    ON avg_ship.country_code = COALESCE(
      "product".iso_country(inv_ship.recipient_country),
      "product".iso_country(o."shipCountry"),
      NULLIF(btrim(o."shipCountry"), '')
    )
  LEFT JOIN product."ExchangeRate" fx
    ON fx.currency = UPPER(btrim(COALESCE(o.currency, 'EUR')))
    AND fx.base = 'EUR'
  LEFT JOIN product."ChannelSaleFeeSetting" sale_fees
    ON sale_fees.id = 'default'
  WHERE o."purchaseDate" IS NOT NULL
) line
LEFT JOIN "product"."mv_overview_sku_meta" meta ON meta.sku = line.sku;

-- Resi imputati alla data di reso, con importi dalla riga ordine originale.
CREATE VIEW "product"."v_order_line_refund"
WITH (security_invoker = true) AS
SELECT
  r."returnDate" AS refund_day,
  r.channel::text AS channel,
  r.sku,
  r.quantity AS refund_units,
  CASE
    WHEN o.quantity > 0 THEN ROUND(o.gross_eur * r.quantity::numeric / o.quantity, 4)
    ELSE 0
  END AS refund_amount_eur,
  CASE
    WHEN o.quantity > 0 THEN ROUND(o.vat_eur * r.quantity::numeric / o.quantity, 4)
    ELSE 0
  END AS refund_vat_eur,
  CASE
    WHEN r.channel = 'TEMU' AND o.quantity > 0
      THEN ROUND(o.referral_eur * r.quantity::numeric / o.quantity, 4)
    ELSE 0
  END AS refund_referral_eur,
  CASE
    WHEN r.channel = 'TEMU' THEN 0
    WHEN r.status IS DISTINCT FROM 'FINANCES'
      AND (
        r.status ILIKE '%inventory%'
        OR r.status ILIKE '%repackaged%'
        OR r.status ILIKE '%sellable%'
      )
      AND UPPER(COALESCE(r.reason, '')) NOT IN (
        'DEFECTIVE',
        'QUALITY_UNACCEPTABLE',
        'DAMAGED_BY_FC',
        'DAMAGED_BY_CARRIER'
      )
      AND o.unit_cost_eur IS NOT NULL
      THEN ROUND(o.unit_cost_eur * r.quantity, 4)
    ELSE 0
  END AS recovered_cogs_eur,
  ROUND(r.quantity * COALESCE(NULLIF(est."fbaFeeDomestic", 0), 3.5), 4) AS return_fee_eur
FROM (
  SELECT DISTINCT ON (r.channel, COALESCE(r."amazonOrderId", r.id::text), r.sku)
    r.*
  FROM product."StoreReturnLine" r
  WHERE (
    (
      r.status IS DISTINCT FROM 'FINANCES'
      AND UPPER(COALESCE(r.reason, '')) NOT IN ('DAMAGED_BY_FC', 'DAMAGED_BY_CARRIER')
    )
    OR (
      r.status = 'FINANCES'
      AND EXISTS (
        SELECT 1
        FROM product."StoreOrderLine" shipped
        WHERE shipped.channel = r.channel
          AND shipped."amazonOrderId" = r."amazonOrderId"
          AND shipped.sku = r.sku
          AND (
            shipped."itemStatus" IS NULL
            OR btrim(shipped."itemStatus") = ''
            OR shipped."itemStatus" = 'Shipped'
          )
      )
    )
  )
  ORDER BY
    r.channel,
    COALESCE(r."amazonOrderId", r.id::text),
    r.sku,
    CASE WHEN r.status = 'FINANCES' THEN 1 ELSE 0 END
) r
LEFT JOIN LATERAL (
  SELECT
    p.quantity,
    p.gross_eur,
    p.vat_eur,
    p.referral_eur,
    p.unit_cost_eur
  FROM "product"."v_order_line_pnl" p
  WHERE p.channel = r.channel::text
    AND p.sku = r.sku
    AND (
      (
        r."amazonOrderId" IS NOT NULL
        AND btrim(r."amazonOrderId") <> ''
        AND p.amazon_order_id = r."amazonOrderId"
      )
      OR r."amazonOrderId" IS NULL
      OR btrim(r."amazonOrderId") = ''
    )
  ORDER BY
    CASE
      WHEN r."amazonOrderId" IS NOT NULL AND p.amazon_order_id = r."amazonOrderId" THEN 0
      ELSE 1
    END,
    CASE WHEN p.is_sold THEN 0 ELSE 1 END,
    p.purchase_day DESC NULLS LAST
  LIMIT 1
) o ON TRUE
LEFT JOIN LATERAL (
  SELECT f."fbaFeeDomestic"
  FROM product."StoreSkuFeeEstimate" f
  WHERE f.channel = 'AMAZON'
    AND f.sku = r.sku
  ORDER BY
    CASE WHEN f."storeKey" = r."storeKey" THEN 0 ELSE 1 END,
    f."updatedAt" DESC
  LIMIT 1
) est ON TRUE;

-- Aggregato giorno × canale (finestra 730 giorni).
CREATE MATERIALIZED VIEW "product"."mv_overview_sales_daily" AS
WITH sold AS (
  SELECT
    p.purchase_day AS day,
    p.channel,
    COUNT(DISTINCT COALESCE(p.amazon_order_id, p.sku || ':' || p.purchase_day::text)) AS orders,
    SUM(p.quantity) AS units,
    SUM(p.gross_eur) AS gross_eur,
    SUM(p.vat_eur) AS vat_eur,
    SUM(p.referral_eur) AS referral_eur,
    SUM(p.digital_eur) AS digital_eur,
    SUM(p.fba_fee_eur) AS fba_fee_eur,
    SUM(p.chargeback_eur) AS chargeback_eur,
    SUM(p.other_fee_eur) AS other_fee_eur,
    SUM(p.refund_commission_eur) AS refund_commission_eur,
    SUM(p.fbm_shipping_eur) AS fbm_shipping_eur,
    SUM(p.cogs_eur) AS cogs_eur,
    SUM(p.quantity) FILTER (WHERE p.unit_cost_eur IS NOT NULL) AS cogs_known_units
  FROM "product"."v_order_line_pnl" p
  WHERE p.is_sold
    AND p.purchase_day >= CURRENT_DATE - INTERVAL '730 days'
  GROUP BY p.purchase_day, p.channel
),
refunds AS (
  SELECT
    r.refund_day AS day,
    r.channel,
    SUM(r.refund_units) AS refund_units,
    SUM(r.refund_amount_eur) AS refund_amount_eur,
    SUM(r.refund_vat_eur) AS refund_vat_eur,
    SUM(r.refund_referral_eur) AS refund_referral_eur,
    SUM(r.recovered_cogs_eur) AS recovered_cogs_eur,
    SUM(r.return_fee_eur) AS return_fee_eur
  FROM "product"."v_order_line_refund" r
  WHERE r.refund_day >= CURRENT_DATE - INTERVAL '730 days'
  GROUP BY r.refund_day, r.channel
)
SELECT
  COALESCE(s.day, r.day) AS day,
  COALESCE(s.channel, r.channel) AS channel,
  COALESCE(s.orders, 0)::int AS orders,
  COALESCE(s.units, 0)::int AS units,
  ROUND(COALESCE(s.gross_eur, 0), 4) AS gross_eur,
  ROUND(COALESCE(s.vat_eur, 0), 4) AS vat_eur,
  ROUND(COALESCE(s.gross_eur, 0) - COALESCE(s.vat_eur, 0), 4) AS net_revenue_eur,
  ROUND(COALESCE(s.referral_eur, 0), 4) AS referral_eur,
  ROUND(COALESCE(s.digital_eur, 0), 4) AS digital_eur,
  ROUND(COALESCE(s.fba_fee_eur, 0), 4) AS fba_fee_eur,
  ROUND(COALESCE(s.chargeback_eur, 0), 4) AS chargeback_eur,
  ROUND(COALESCE(s.other_fee_eur, 0), 4) AS other_fee_eur,
  ROUND(COALESCE(s.refund_commission_eur, 0), 4) AS refund_commission_eur,
  ROUND(COALESCE(s.fbm_shipping_eur, 0), 4) AS fbm_shipping_eur,
  ROUND(COALESCE(s.cogs_eur, 0), 4) AS cogs_eur,
  COALESCE(s.cogs_known_units, 0)::int AS cogs_known_units,
  COALESCE(r.refund_units, 0)::int AS refund_units,
  ROUND(COALESCE(r.refund_amount_eur, 0), 4) AS refund_amount_eur,
  ROUND(COALESCE(r.refund_vat_eur, 0), 4) AS refund_vat_eur,
  ROUND(COALESCE(r.refund_referral_eur, 0), 4) AS refund_referral_eur,
  ROUND(COALESCE(r.recovered_cogs_eur, 0), 4) AS recovered_cogs_eur,
  ROUND(COALESCE(r.return_fee_eur, 0), 4) AS return_fee_eur,
  ROUND(
    (COALESCE(s.gross_eur, 0) - COALESCE(r.refund_amount_eur, 0))
    - (COALESCE(s.vat_eur, 0) - COALESCE(r.refund_vat_eur, 0))
    - (COALESCE(s.referral_eur, 0) - COALESCE(r.refund_referral_eur, 0))
    - COALESCE(s.digital_eur, 0)
    - COALESCE(s.fba_fee_eur, 0)
    - COALESCE(s.chargeback_eur, 0)
    - COALESCE(s.other_fee_eur, 0)
    - COALESCE(s.refund_commission_eur, 0)
    - COALESCE(s.fbm_shipping_eur, 0)
    - (COALESCE(s.cogs_eur, 0) - COALESCE(r.recovered_cogs_eur, 0))
    - COALESCE(r.return_fee_eur, 0),
    4
  ) AS profit_eur
FROM sold s
FULL OUTER JOIN refunds r
  ON r.day = s.day AND r.channel = s.channel;

CREATE UNIQUE INDEX "mv_overview_sales_daily_day_channel_uidx"
  ON "product"."mv_overview_sales_daily" (day, channel);

-- Aggregato giorno × canale × SKU (finestra 730 giorni).
CREATE MATERIALIZED VIEW "product"."mv_overview_sku_daily" AS
WITH sold AS (
  SELECT
    p.purchase_day AS day,
    p.channel,
    p.sku,
    MAX(p.asin) AS asin,
    MAX(p.product_name) AS product_name,
    SUM(p.quantity) AS units,
    SUM(p.gross_eur) AS gross_eur,
    SUM(p.vat_eur) AS vat_eur,
    SUM(p.referral_eur) AS referral_eur,
    SUM(p.digital_eur) AS digital_eur,
    SUM(p.fba_fee_eur) AS fba_fee_eur,
    SUM(p.chargeback_eur) AS chargeback_eur,
    SUM(p.other_fee_eur) AS other_fee_eur,
    SUM(p.refund_commission_eur) AS refund_commission_eur,
    SUM(p.fbm_shipping_eur) AS fbm_shipping_eur,
    SUM(p.cogs_eur) AS cogs_eur
  FROM "product"."v_order_line_pnl" p
  WHERE p.is_sold
    AND p.purchase_day >= CURRENT_DATE - INTERVAL '730 days'
  GROUP BY p.purchase_day, p.channel, p.sku
),
refunds AS (
  SELECT
    r.refund_day AS day,
    r.channel,
    r.sku,
    SUM(r.refund_units) AS refund_units,
    SUM(r.refund_amount_eur) AS refund_amount_eur,
    SUM(r.refund_vat_eur) AS refund_vat_eur,
    SUM(r.refund_referral_eur) AS refund_referral_eur,
    SUM(r.recovered_cogs_eur) AS recovered_cogs_eur,
    SUM(r.return_fee_eur) AS return_fee_eur
  FROM "product"."v_order_line_refund" r
  WHERE r.refund_day >= CURRENT_DATE - INTERVAL '730 days'
  GROUP BY r.refund_day, r.channel, r.sku
)
SELECT
  COALESCE(s.day, r.day) AS day,
  COALESCE(s.channel, r.channel) AS channel,
  COALESCE(s.sku, r.sku) AS sku,
  s.asin,
  s.product_name,
  COALESCE(s.units, 0)::int AS units,
  ROUND(COALESCE(s.gross_eur, 0), 4) AS gross_eur,
  ROUND(COALESCE(s.gross_eur, 0) - COALESCE(s.vat_eur, 0), 4) AS net_revenue_eur,
  COALESCE(r.refund_units, 0)::int AS refund_units,
  ROUND(
    (COALESCE(s.gross_eur, 0) - COALESCE(r.refund_amount_eur, 0))
    - (COALESCE(s.vat_eur, 0) - COALESCE(r.refund_vat_eur, 0))
    - (COALESCE(s.referral_eur, 0) - COALESCE(r.refund_referral_eur, 0))
    - COALESCE(s.digital_eur, 0)
    - COALESCE(s.fba_fee_eur, 0)
    - COALESCE(s.chargeback_eur, 0)
    - COALESCE(s.other_fee_eur, 0)
    - COALESCE(s.refund_commission_eur, 0)
    - COALESCE(s.fbm_shipping_eur, 0)
    - (COALESCE(s.cogs_eur, 0) - COALESCE(r.recovered_cogs_eur, 0))
    - COALESCE(r.return_fee_eur, 0),
    4
  ) AS profit_eur
FROM sold s
FULL OUTER JOIN refunds r
  ON r.day = s.day AND r.channel = s.channel AND r.sku = s.sku;

CREATE UNIQUE INDEX "mv_overview_sku_daily_day_channel_sku_uidx"
  ON "product"."mv_overview_sku_daily" (day, channel, sku);

CREATE INDEX "mv_overview_sku_daily_sku_idx"
  ON "product"."mv_overview_sku_daily" (sku);
