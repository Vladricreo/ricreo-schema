-- F1 is_sold: spediti + in attesa (esclude cancelled/canceled/refunded/unfulfillable e qty<=0)
-- F2 refund_referral_eur: solo referral (include già DSF)
-- F3 country/fulfillment matview refund-aware (sold FULL JOIN refunds, chiave refund_day)
-- F4 colonne VAT exclusive + gift wrap; fallback IVA in v_order_line_pnl
-- F5 seasonality: bucket UTC + importi EUR + qty>0
-- recovered_cogs_eur resta 0 di proposito: il COGS si perde anche sui restock vendibili.
-- IVA eBay resta 0: IVA eBay non gestita in-app.
-- Backfill storico vatExclusive*/giftWrap* solo con reimport Settings (overwrite).

ALTER TABLE "product"."StoreOrderLine"
  ADD COLUMN IF NOT EXISTS "giftWrapPrice" DECIMAL(12,2),
  ADD COLUMN IF NOT EXISTS "giftWrapTax" DECIMAL(12,2),
  ADD COLUMN IF NOT EXISTS "vatExclusiveItemPrice" DECIMAL(12,2),
  ADD COLUMN IF NOT EXISTS "vatExclusiveShippingPrice" DECIMAL(12,2);

DROP MATERIALIZED VIEW IF EXISTS "product"."mv_overview_sales_daily";
DROP MATERIALIZED VIEW IF EXISTS "product"."mv_overview_sku_daily";
DROP MATERIALIZED VIEW IF EXISTS "product"."mv_sales_analytics_refund_daily";
DROP MATERIALIZED VIEW IF EXISTS "product"."mv_overview_country_daily";
DROP MATERIALIZED VIEW IF EXISTS "product"."mv_overview_fulfillment_daily";
DROP MATERIALIZED VIEW IF EXISTS "product"."mv_sales_analytics_daily";
DROP MATERIALIZED VIEW IF EXISTS "product"."mv_order_seasonality";

CREATE OR REPLACE VIEW "product"."v_order_line_pnl" AS
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
    WHEN line.is_fba THEN 'FBA'::text
    WHEN line.is_fbm THEN 'FBM'::text
    ELSE COALESCE(NULLIF(btrim(line.fulfillment_channel), ''), 'FBM'::text)
  END AS fulfillment,
  line.is_sold,
  line.quantity,
  CASE WHEN line.is_sold THEN round(line.gross_local * line.eur_factor, 4) ELSE 0::numeric END AS gross_eur,
  CASE WHEN line.is_sold THEN round(line.vat_local * line.eur_factor, 4) ELSE 0::numeric END AS vat_eur,
  CASE WHEN line.is_sold THEN round(line.referral_local * line.eur_factor, 4) ELSE 0::numeric END AS referral_eur,
  CASE WHEN line.is_sold THEN round(line.digital_local * line.eur_factor, 4) ELSE 0::numeric END AS digital_eur,
  CASE WHEN line.is_sold THEN round(line.fba_fee_local * line.eur_factor, 4) ELSE 0::numeric END AS fba_fee_eur,
  CASE WHEN line.is_sold THEN round(line.chargeback_local * line.eur_factor, 4) ELSE 0::numeric END AS chargeback_eur,
  CASE WHEN line.is_sold THEN round(line.other_fee_local * line.eur_factor, 4) ELSE 0::numeric END AS other_fee_eur,
  CASE WHEN line.is_sold THEN round(line.refund_commission_local * line.eur_factor, 4) ELSE 0::numeric END AS refund_commission_eur,
  CASE WHEN line.is_sold THEN round(line.fbm_shipping_eur, 4) ELSE 0::numeric END AS fbm_shipping_eur,
  meta.unit_cost_eur,
  CASE
    WHEN line.is_sold AND meta.unit_cost_eur IS NOT NULL
    THEN round(meta.unit_cost_eur * GREATEST(line.quantity, 0)::numeric, 4)
    ELSE 0::numeric
  END AS cogs_eur,
  line.has_fee_estimate,
  line.sales_channel,
  line.order_item_id,
  CASE WHEN line.is_sold THEN round(line.customer_shipping_local * line.eur_factor, 4) ELSE 0::numeric END AS customer_shipping_eur,
  CASE WHEN line.is_sold THEN round(line.customer_shipping_tax_local * line.eur_factor, 4) ELSE 0::numeric END AS customer_shipping_tax_eur,
  line.cost_source,
  line.fbm_shipping_source,
  meta.image_url
FROM (
  SELECT
    o.channel::text AS channel,
    o."storeKey" AS store_key,
    o."salesChannel" AS sales_channel,
    o."amazonOrderId" AS amazon_order_id,
    o."orderItemId" AS order_item_id,
    o."purchaseDate"::date AS purchase_day,
    o.sku,
    o.asin,
    o."productName" AS product_name,
    GREATEST(o.quantity, 0) AS quantity,
    o."fulfillmentChannel" AS fulfillment_channel,
    lower(btrim(COALESCE(o."itemStatus", ''))) NOT IN ('cancelled', 'canceled', 'refunded', 'unfulfillable')
      AND COALESCE(o.quantity, 0) > 0 AS is_sold,
    o."fulfillmentChannel" = 'FBA'::text AS is_fba,
    o."fulfillmentChannel" = 'FBM'::text
      OR o.channel::text IS DISTINCT FROM 'AMAZON'::text
      AND (o."fulfillmentChannel" IS NULL OR btrim(o."fulfillmentChannel") = '') AS is_fbm,
    COALESCE(
      product.iso_country(inv_ship.recipient_country),
      product.iso_country(o."shipCountry"),
      NULLIF(btrim(o."shipCountry"), '')::character varying
    ) AS dest_country,
    COALESCE(o."itemPrice", 0) - COALESCE(o."itemPromotionDiscount", 0)
      + COALESCE(o."shippingPrice", 0) - COALESCE(o."shipPromotionDiscount", 0)
      + COALESCE(o."giftWrapPrice", 0) AS gross_local,
    CASE
      WHEN o.channel::text = 'EBAY'::text THEN 0::numeric
      ELSE
        COALESCE(NULLIF(o."itemTax", 0), GREATEST(0, o."itemPrice" - o."vatExclusiveItemPrice"), 0)
        + COALESCE(NULLIF(o."shippingTax", 0), GREATEST(0, o."shippingPrice" - o."vatExclusiveShippingPrice"), 0)
        + COALESCE(o."giftWrapTax", 0)
    END AS vat_local,
    COALESCE(o."shippingPrice", 0) - COALESCE(o."shipPromotionDiscount", 0) AS customer_shipping_local,
    COALESCE(
      NULLIF(o."shippingTax", 0),
      GREATEST(0, o."shippingPrice" - o."vatExclusiveShippingPrice"),
      0
    ) AS customer_shipping_tax_local,
    CASE
      WHEN o.currency IS NULL OR btrim(o.currency) = '' OR upper(btrim(o.currency)) = 'EUR'
        OR fx.rate IS NULL OR fx.rate <= 0 THEN 1::numeric
      ELSE 1::numeric / fx.rate
    END AS eur_factor,
    COALESCE(
      CASE WHEN fee."realCosts" THEN fee."referralFee" ELSE fee."provisionalReferralFee" END,
      0
    ) AS referral_local,
    COALESCE(
      CASE WHEN fee."realCosts" THEN fee."digitalServicesFee" ELSE fee."provisionalDigitalServicesFee" END,
      0
    ) AS digital_local,
    CASE
      WHEN o."fulfillmentChannel" = 'FBA'::text THEN COALESCE(
        CASE WHEN fee."realCosts" THEN fee."fbaFulfillmentFee" ELSE fee."provisionalFbaFee" END,
        0
      )
      ELSE 0::numeric
    END AS fba_fee_local,
    CASE
      WHEN o."fulfillmentChannel" = 'FBA'::text THEN COALESCE(
        CASE WHEN fee."realCosts" THEN fee."shippingChargeback" ELSE fee."provisionalShippingChargeback" END,
        0
      )
      ELSE 0::numeric
    END AS chargeback_local,
    COALESCE(NULLIF(fee."otherFee", 0), 0) AS other_fee_local,
    COALESCE(NULLIF(fee."refundCommission", 0), 0) AS refund_commission_local,
    CASE
      WHEN o."fulfillmentChannel" = 'FBA'::text THEN 0::numeric
      WHEN NOT (
        o."fulfillmentChannel" = 'FBM'::text
        OR o.channel::text IS DISTINCT FROM 'AMAZON'::text
        AND (o."fulfillmentChannel" IS NULL OR btrim(o."fulfillmentChannel") = '')
      ) THEN 0::numeric
      WHEN inv_ship.unit_cost IS NOT NULL THEN inv_ship.unit_cost * GREATEST(o.quantity, 0)::numeric
      ELSE COALESCE(fee."provisionalFbmShipping", 0)
    END AS fbm_shipping_eur,
    CASE
      WHEN o."fulfillmentChannel" = 'FBA'::text THEN 'amazon'::text
      WHEN NOT (
        o."fulfillmentChannel" = 'FBM'::text
        OR o.channel::text IS DISTINCT FROM 'AMAZON'::text
        AND (o."fulfillmentChannel" IS NULL OR btrim(o."fulfillmentChannel") = '')
      ) THEN 'none'::text
      WHEN inv_ship.unit_cost IS NOT NULL THEN 'shipment'::text
      WHEN fee."provisionalShippingSource" = 'shipping_price'::text THEN 'default'::text
      WHEN fee."provisionalShippingSource" = 'shipping_average'::text THEN 'average'::text
      WHEN COALESCE(fee."provisionalFbmShipping", 0) > 0 THEN 'default'::text
      ELSE 'none'::text
    END AS fbm_shipping_source,
    CASE
      WHEN fee."realCosts" THEN 'real'::text
      WHEN fee."provisionalAt" IS NOT NULL THEN 'provisional'::text
      ELSE 'none'::text
    END AS cost_source,
    COALESCE(fee."realCosts", false)
      OR COALESCE(fee."provisionalReferralFee", 0) > 0
      OR COALESCE(fee."provisionalFbaFee", 0) > 0
      OR COALESCE(fee."referralFee", 0) > 0
      OR COALESCE(fee."fbaFulfillmentFee", 0) > 0
      OR COALESCE(fee."otherFee", 0) > 0 AS has_fee_estimate
  FROM product."StoreOrderLine" o
  LEFT JOIN LATERAL (
    SELECT
      sf."fbaFulfillmentFee",
      sf."referralFee",
      sf."digitalServicesFee",
      sf."shippingChargeback",
      sf."refundCommission",
      sf."otherFee",
      sf."realCosts",
      sf."provisionalReferralFee",
      sf."provisionalDigitalServicesFee",
      sf."provisionalFbaFee",
      sf."provisionalShippingChargeback",
      sf."provisionalFbmShipping",
      sf."provisionalShippingSource",
      sf."provisionalAt"
    FROM product."StoreOrderFee" sf
    WHERE sf.channel = o.channel
      AND sf."amazonOrderId" = o."amazonOrderId"
      AND (
        sf."orderItemId" <> '' AND sf."orderItemId" = COALESCE(o."orderItemId", '')
        OR sf.sku = o.sku
      )
    ORDER BY
      CASE WHEN sf."realCosts" THEN 0 ELSE 1 END,
      CASE WHEN sf."orderItemId" <> '' AND sf."orderItemId" = COALESCE(o."orderItemId", '') THEN 0 ELSE 1 END,
      CASE WHEN sf.sku = o.sku THEN 0 ELSE 1 END
    LIMIT 1
  ) fee ON true
  LEFT JOIN LATERAL (
    SELECT
      CASE
        WHEN s."shippingCost" IS NOT NULL AND s."shippingCost" > 0 AND qty.total_qty > 0
        THEN s."shippingCost" / qty.total_qty::numeric
        ELSE NULL::numeric
      END AS unit_cost,
      s."recipientCountry" AS recipient_country
    FROM inventory."Shipment" s
    JOIN LATERAL (
      SELECT COALESCE(sum(GREATEST(l.quantity, 0)), 0)::bigint AS total_qty
      FROM inventory."ShipmentLine" l
      WHERE l."shipmentId" = s.id
    ) qty ON true
    WHERE o."amazonOrderId" IS NOT NULL
      AND btrim(o."amazonOrderId") <> ''
      AND s."shipmentType" IS DISTINCT FROM 'FBA'::inventory."ShipmentType"
      AND (
        s."marketplaceOrderId" = o."amazonOrderId"
        OR s."marketplaceOrderId" = o."orderItemId"
        OR o.channel = 'TEMU'::product."StoreChannel"
          AND s."marketplaceOrderId" = concat('PO-', regexp_replace(o."amazonOrderId", '^PO-', '', 'i'))
        OR o.channel = 'TEMU'::product."StoreChannel"
          AND o."orderItemId" IS NOT NULL
          AND s."marketplaceOrderId" = concat('PO-', regexp_replace(o."orderItemId", '^PO-', '', 'i'))
      )
    ORDER BY
      (
        EXISTS (
          SELECT 1
          FROM inventory."ShipmentLine" sl
          LEFT JOIN inventory."Sku" sku ON sku.id = sl."skuId"
          WHERE sl."shipmentId" = s.id
            AND COALESCE(sl."skuCodeSnapshot", sku.code) = o.sku
        )
      ) DESC,
      COALESCE(s."shippedAt", s."orderedAt") DESC NULLS LAST
    LIMIT 1
  ) inv_ship ON true
  LEFT JOIN product."ExchangeRate" fx
    ON fx.currency = upper(btrim(COALESCE(o.currency, 'EUR')))
   AND fx.base = 'EUR'
  WHERE o."purchaseDate" IS NOT NULL
) line
LEFT JOIN product.mv_overview_sku_meta meta ON meta.sku = line.sku;

CREATE OR REPLACE VIEW "product"."v_order_line_refund" AS
WITH returns AS (
  SELECT DISTINCT ON (r_1.channel, COALESCE(r_1."amazonOrderId", r_1.id), r_1.sku)
    r_1.id,
    r_1.channel,
    r_1."storeKey",
    r_1."idempotencyKey",
    r_1."amazonOrderId",
    r_1.sku,
    r_1.asin,
    r_1."productName",
    r_1.quantity,
    r_1."returnDate",
    r_1.reason,
    r_1.status,
    r_1."amazonFulfillment",
    r_1."createdAt",
    r_1."updatedAt",
    r_1."reasonDescription"
  FROM product."StoreReturnLine" r_1
  WHERE r_1.status IS DISTINCT FROM 'FINANCES'
    AND (upper(COALESCE(r_1.reason, '')) <> ALL (ARRAY['DAMAGED_BY_FC'::text, 'DAMAGED_BY_CARRIER'::text]))
    OR r_1.status = 'FINANCES'
    AND EXISTS (
      SELECT 1
      FROM product."StoreOrderLine" sold
      WHERE sold.channel = r_1.channel
        AND sold."amazonOrderId" = r_1."amazonOrderId"
        AND sold.sku = r_1.sku
        AND COALESCE(sold.quantity, 0) > 0
        AND lower(btrim(COALESCE(sold."itemStatus", '')))
          NOT IN ('cancelled', 'canceled', 'refunded', 'unfulfillable')
    )
  ORDER BY
    r_1.channel,
    COALESCE(r_1."amazonOrderId", r_1.id),
    r_1.sku,
    CASE WHEN r_1.status = 'FINANCES' THEN 1 ELSE 0 END
)
SELECT
  r."returnDate" AS refund_day,
  r.channel::text AS channel,
  r.sku,
  r.quantity AS refund_units,
  CASE
    WHEN o.quantity > 0 THEN round(o.gross_eur * r.quantity::numeric / o.quantity::numeric, 4)
    ELSE 0::numeric
  END AS refund_amount_eur,
  CASE
    WHEN o.quantity > 0 THEN round(o.vat_eur * r.quantity::numeric / o.quantity::numeric, 4)
    ELSE 0::numeric
  END AS refund_vat_eur,
  CASE
    WHEN r.channel = 'ETSY'::product."StoreChannel" THEN 0::numeric
    WHEN o.quantity > 0 THEN round(COALESCE(o.referral_eur, 0) * r.quantity::numeric / o.quantity::numeric, 4)
    ELSE 0::numeric
  END AS refund_referral_eur,
  0::numeric AS recovered_cogs_eur,
  CASE
    WHEN r.channel = 'AMAZON'::product."StoreChannel"
      AND r.status IS DISTINCT FROM 'FINANCES'
      AND (o.fulfillment = 'FBA' OR upper(btrim(COALESCE(r."amazonFulfillment", ''))) = 'FBA')
    THEN round(r.quantity::numeric * COALESCE(NULLIF(est."fbaFeeDomestic", 0), 3.5), 4)
    ELSE 0::numeric
  END AS return_fee_eur,
  r."storeKey" AS store_key,
  CASE WHEN restock.is_sellable THEN r.quantity ELSE 0 END AS sellable_units,
  COALESCE(NULLIF(btrim(o.ship_country::text), ''), 'XX') AS country_code,
  COALESCE(o.fulfillment, 'FBM') AS fulfillment
FROM returns r
LEFT JOIN LATERAL (
  SELECT
    p.quantity,
    p.gross_eur,
    p.vat_eur,
    p.referral_eur,
    p.digital_eur,
    p.unit_cost_eur,
    p.fulfillment,
    p.ship_country
  FROM product.v_order_line_pnl p
  WHERE p.channel = r.channel::text
    AND p.sku = r.sku
    AND (
      r."amazonOrderId" IS NOT NULL AND btrim(r."amazonOrderId") <> '' AND p.amazon_order_id = r."amazonOrderId"
      OR r."amazonOrderId" IS NULL
      OR btrim(r."amazonOrderId") = ''
    )
  ORDER BY
    CASE WHEN r."amazonOrderId" IS NOT NULL AND p.amazon_order_id = r."amazonOrderId" THEN 0 ELSE 1 END,
    CASE WHEN p.is_sold THEN 0 ELSE 1 END,
    p.purchase_day DESC NULLS LAST
  LIMIT 1
) o ON true
LEFT JOIN LATERAL (
  SELECT
    (upper(COALESCE(r.reason, '')) <> ALL (ARRAY['DEFECTIVE', 'QUALITY_UNACCEPTABLE', 'DAMAGED_BY_FC', 'DAMAGED_BY_CARRIER']))
    AND (
      r.channel = 'AMAZON'::product."StoreChannel"
        AND (o.fulfillment = 'FBA' OR upper(btrim(COALESCE(r."amazonFulfillment", ''))) = 'FBA')
      OR r.status IS DISTINCT FROM 'FINANCES'
        AND (r.status ~~* '%inventory%' OR r.status ~~* '%repackaged%' OR r.status ~~* '%sellable%')
    ) AS is_sellable
) restock ON true
LEFT JOIN LATERAL (
  SELECT f."fbaFeeDomestic"
  FROM product."StoreSkuFeeEstimate" f
  WHERE f.channel = 'AMAZON'::product."StoreChannel"
    AND f.sku = r.sku
  ORDER BY
    CASE WHEN f."storeKey" = r."storeKey" THEN 0 ELSE 1 END,
    f."updatedAt" DESC
  LIMIT 1
) est ON true;

CREATE MATERIALIZED VIEW "product"."mv_overview_sales_daily" AS
WITH sold AS (
  SELECT
    p.purchase_day AS day,
    p.channel,
    count(DISTINCT COALESCE(p.amazon_order_id, (p.sku || ':') || p.purchase_day::text)) AS orders,
    sum(p.quantity) AS units,
    sum(p.gross_eur) AS gross_eur,
    sum(p.vat_eur) AS vat_eur,
    sum(p.referral_eur) AS referral_eur,
    sum(p.digital_eur) AS digital_eur,
    sum(p.fba_fee_eur) AS fba_fee_eur,
    sum(p.chargeback_eur) AS chargeback_eur,
    sum(p.other_fee_eur) AS other_fee_eur,
    sum(p.refund_commission_eur) AS refund_commission_eur,
    sum(p.fbm_shipping_eur) AS fbm_shipping_eur,
    sum(p.cogs_eur) AS cogs_eur,
    sum(p.quantity) FILTER (WHERE p.unit_cost_eur IS NOT NULL) AS cogs_known_units
  FROM product.v_order_line_pnl p
  WHERE p.is_sold AND p.purchase_day >= (CURRENT_DATE - INTERVAL '730 days')
  GROUP BY p.purchase_day, p.channel
), refunds AS (
  SELECT
    r_1.refund_day AS day,
    r_1.channel,
    sum(r_1.refund_units) AS refund_units,
    sum(r_1.refund_amount_eur) AS refund_amount_eur,
    sum(r_1.refund_vat_eur) AS refund_vat_eur,
    sum(r_1.refund_referral_eur) AS refund_referral_eur,
    sum(r_1.recovered_cogs_eur) AS recovered_cogs_eur,
    sum(r_1.return_fee_eur) AS return_fee_eur
  FROM product.v_order_line_refund r_1
  WHERE r_1.refund_day >= (CURRENT_DATE - INTERVAL '730 days')
  GROUP BY r_1.refund_day, r_1.channel
)
SELECT
  COALESCE(s.day, r.day) AS day,
  COALESCE(s.channel, r.channel) AS channel,
  COALESCE(s.orders, 0)::integer AS orders,
  COALESCE(s.units, 0)::integer AS units,
  round(COALESCE(s.gross_eur, 0), 4) AS gross_eur,
  round(COALESCE(s.vat_eur, 0), 4) AS vat_eur,
  round(COALESCE(s.gross_eur, 0) - COALESCE(s.vat_eur, 0), 4) AS net_revenue_eur,
  round(COALESCE(s.referral_eur, 0), 4) AS referral_eur,
  round(COALESCE(s.digital_eur, 0), 4) AS digital_eur,
  round(COALESCE(s.fba_fee_eur, 0), 4) AS fba_fee_eur,
  round(COALESCE(s.chargeback_eur, 0), 4) AS chargeback_eur,
  round(COALESCE(s.other_fee_eur, 0), 4) AS other_fee_eur,
  round(COALESCE(s.refund_commission_eur, 0), 4) AS refund_commission_eur,
  round(COALESCE(s.fbm_shipping_eur, 0), 4) AS fbm_shipping_eur,
  round(COALESCE(s.cogs_eur, 0), 4) AS cogs_eur,
  COALESCE(s.cogs_known_units, 0)::integer AS cogs_known_units,
  COALESCE(r.refund_units, 0)::integer AS refund_units,
  round(COALESCE(r.refund_amount_eur, 0), 4) AS refund_amount_eur,
  round(COALESCE(r.refund_vat_eur, 0), 4) AS refund_vat_eur,
  round(COALESCE(r.refund_referral_eur, 0), 4) AS refund_referral_eur,
  round(COALESCE(r.recovered_cogs_eur, 0), 4) AS recovered_cogs_eur,
  round(COALESCE(r.return_fee_eur, 0), 4) AS return_fee_eur,
  round(
    COALESCE(s.gross_eur, 0) - COALESCE(r.refund_amount_eur, 0)
    - (COALESCE(s.vat_eur, 0) - COALESCE(r.refund_vat_eur, 0))
    - (COALESCE(s.referral_eur, 0) - COALESCE(r.refund_referral_eur, 0))
    - COALESCE(s.fba_fee_eur, 0)
    - COALESCE(s.chargeback_eur, 0)
    - COALESCE(s.other_fee_eur, 0)
    - COALESCE(s.refund_commission_eur, 0)
    - COALESCE(s.fbm_shipping_eur, 0)
    - (COALESCE(s.cogs_eur, 0) - COALESCE(r.recovered_cogs_eur, 0))
    - COALESCE(r.return_fee_eur, 0)
  , 4) AS profit_eur
FROM sold s
FULL JOIN refunds r ON r.day = s.day AND r.channel = s.channel
WITH NO DATA;

CREATE UNIQUE INDEX mv_overview_sales_daily_day_channel_uidx
  ON product.mv_overview_sales_daily USING btree (day, channel);

CREATE MATERIALIZED VIEW "product"."mv_overview_sku_daily" AS
WITH sold AS (
  SELECT
    p.purchase_day AS day,
    p.channel,
    p.sku,
    max(p.asin) AS asin,
    max(p.product_name) AS product_name,
    sum(p.quantity) AS units,
    sum(p.gross_eur) AS gross_eur,
    sum(p.vat_eur) AS vat_eur,
    sum(p.referral_eur) AS referral_eur,
    sum(p.fba_fee_eur) AS fba_fee_eur,
    sum(p.chargeback_eur) AS chargeback_eur,
    sum(p.other_fee_eur) AS other_fee_eur,
    sum(p.refund_commission_eur) AS refund_commission_eur,
    sum(p.fbm_shipping_eur) AS fbm_shipping_eur,
    sum(p.cogs_eur) AS cogs_eur
  FROM product.v_order_line_pnl p
  WHERE p.is_sold AND p.purchase_day >= (CURRENT_DATE - INTERVAL '730 days')
  GROUP BY p.purchase_day, p.channel, p.sku
), refunds AS (
  SELECT
    r_1.refund_day AS day,
    r_1.channel,
    r_1.sku,
    sum(r_1.refund_units) AS refund_units,
    sum(r_1.refund_amount_eur) AS refund_amount_eur,
    sum(r_1.refund_vat_eur) AS refund_vat_eur,
    sum(r_1.refund_referral_eur) AS refund_referral_eur,
    sum(r_1.recovered_cogs_eur) AS recovered_cogs_eur,
    sum(r_1.return_fee_eur) AS return_fee_eur
  FROM product.v_order_line_refund r_1
  WHERE r_1.refund_day >= (CURRENT_DATE - INTERVAL '730 days')
  GROUP BY r_1.refund_day, r_1.channel, r_1.sku
)
SELECT
  COALESCE(s.day, r.day) AS day,
  COALESCE(s.channel, r.channel) AS channel,
  COALESCE(s.sku, r.sku) AS sku,
  s.asin,
  s.product_name,
  COALESCE(s.units, 0)::integer AS units,
  round(COALESCE(s.gross_eur, 0), 4) AS gross_eur,
  round(COALESCE(s.gross_eur, 0) - COALESCE(s.vat_eur, 0), 4) AS net_revenue_eur,
  COALESCE(r.refund_units, 0)::integer AS refund_units,
  round(
    COALESCE(s.gross_eur, 0) - COALESCE(r.refund_amount_eur, 0)
    - (COALESCE(s.vat_eur, 0) - COALESCE(r.refund_vat_eur, 0))
    - (COALESCE(s.referral_eur, 0) - COALESCE(r.refund_referral_eur, 0))
    - COALESCE(s.fba_fee_eur, 0)
    - COALESCE(s.chargeback_eur, 0)
    - COALESCE(s.other_fee_eur, 0)
    - COALESCE(s.refund_commission_eur, 0)
    - COALESCE(s.fbm_shipping_eur, 0)
    - (COALESCE(s.cogs_eur, 0) - COALESCE(r.recovered_cogs_eur, 0))
    - COALESCE(r.return_fee_eur, 0)
  , 4) AS profit_eur
FROM sold s
FULL JOIN refunds r ON r.day = s.day AND r.channel = s.channel AND r.sku = s.sku
WITH NO DATA;

CREATE UNIQUE INDEX mv_overview_sku_daily_day_channel_sku_uidx
  ON product.mv_overview_sku_daily USING btree (day, channel, sku);
CREATE INDEX mv_overview_sku_daily_sku_idx
  ON product.mv_overview_sku_daily USING btree (sku);

CREATE MATERIALIZED VIEW "product"."mv_overview_country_daily" AS
WITH sold AS (
  SELECT
    p.purchase_day AS day,
    COALESCE(NULLIF(btrim(p.ship_country::text), ''), 'XX') AS country_code,
    sum(p.quantity) AS units,
    sum(p.gross_eur) AS gross_eur,
    sum(p.vat_eur) AS vat_eur,
    sum(p.referral_eur) AS referral_eur,
    sum(p.fba_fee_eur) AS fba_fee_eur,
    sum(p.chargeback_eur) AS chargeback_eur,
    sum(p.other_fee_eur) AS other_fee_eur,
    sum(p.refund_commission_eur) AS refund_commission_eur,
    sum(p.fbm_shipping_eur) AS fbm_shipping_eur,
    sum(p.cogs_eur) AS cogs_eur
  FROM product.v_order_line_pnl p
  WHERE p.is_sold AND p.purchase_day >= (CURRENT_DATE - INTERVAL '730 days')
  GROUP BY p.purchase_day, COALESCE(NULLIF(btrim(p.ship_country::text), ''), 'XX')
), refunds AS (
  SELECT
    r_1.refund_day AS day,
    COALESCE(NULLIF(btrim(r_1.country_code::text), ''), 'XX') AS country_code,
    sum(r_1.refund_amount_eur) AS refund_amount_eur,
    sum(r_1.refund_vat_eur) AS refund_vat_eur,
    sum(r_1.refund_referral_eur) AS refund_referral_eur,
    sum(r_1.recovered_cogs_eur) AS recovered_cogs_eur,
    sum(r_1.return_fee_eur) AS return_fee_eur
  FROM product.v_order_line_refund r_1
  WHERE r_1.refund_day >= (CURRENT_DATE - INTERVAL '730 days')
  GROUP BY r_1.refund_day, COALESCE(NULLIF(btrim(r_1.country_code::text), ''), 'XX')
)
SELECT
  COALESCE(s.day, r.day) AS day,
  COALESCE(s.country_code, r.country_code) AS country_code,
  COALESCE(s.units, 0)::integer AS units,
  round(COALESCE(s.gross_eur, 0) - COALESCE(s.vat_eur, 0), 4) AS net_revenue_eur,
  round(
    COALESCE(s.gross_eur, 0) - COALESCE(r.refund_amount_eur, 0)
    - (COALESCE(s.vat_eur, 0) - COALESCE(r.refund_vat_eur, 0))
    - (COALESCE(s.referral_eur, 0) - COALESCE(r.refund_referral_eur, 0))
    - COALESCE(s.fba_fee_eur, 0)
    - COALESCE(s.chargeback_eur, 0)
    - COALESCE(s.other_fee_eur, 0)
    - COALESCE(s.refund_commission_eur, 0)
    - COALESCE(s.fbm_shipping_eur, 0)
    - (COALESCE(s.cogs_eur, 0) - COALESCE(r.recovered_cogs_eur, 0))
    - COALESCE(r.return_fee_eur, 0)
  , 4) AS profit_eur
FROM sold s
FULL JOIN refunds r ON r.day = s.day AND r.country_code = s.country_code
WITH NO DATA;

CREATE UNIQUE INDEX mv_overview_country_daily_day_country_uidx
  ON product.mv_overview_country_daily USING btree (day, country_code);

CREATE MATERIALIZED VIEW "product"."mv_overview_fulfillment_daily" AS
WITH sold AS (
  SELECT
    p.purchase_day AS day,
    CASE WHEN p.fulfillment = 'FBA' THEN 'FBA' ELSE 'FBM' END AS fulfillment,
    sum(p.quantity) AS units,
    sum(p.gross_eur) AS gross_eur,
    sum(p.vat_eur) AS vat_eur,
    sum(p.referral_eur) AS referral_eur,
    sum(p.fba_fee_eur) AS fba_fee_eur,
    sum(p.chargeback_eur) AS chargeback_eur,
    sum(p.other_fee_eur) AS other_fee_eur,
    sum(p.refund_commission_eur) AS refund_commission_eur,
    sum(p.fbm_shipping_eur) AS fbm_shipping_eur,
    sum(p.cogs_eur) AS cogs_eur
  FROM product.v_order_line_pnl p
  WHERE p.is_sold AND p.purchase_day >= (CURRENT_DATE - INTERVAL '730 days')
  GROUP BY p.purchase_day, CASE WHEN p.fulfillment = 'FBA' THEN 'FBA' ELSE 'FBM' END
), refunds AS (
  SELECT
    r_1.refund_day AS day,
    CASE WHEN r_1.fulfillment = 'FBA' THEN 'FBA' ELSE 'FBM' END AS fulfillment,
    sum(r_1.refund_amount_eur) AS refund_amount_eur,
    sum(r_1.refund_vat_eur) AS refund_vat_eur,
    sum(r_1.refund_referral_eur) AS refund_referral_eur,
    sum(r_1.recovered_cogs_eur) AS recovered_cogs_eur,
    sum(r_1.return_fee_eur) AS return_fee_eur
  FROM product.v_order_line_refund r_1
  WHERE r_1.refund_day >= (CURRENT_DATE - INTERVAL '730 days')
  GROUP BY r_1.refund_day, CASE WHEN r_1.fulfillment = 'FBA' THEN 'FBA' ELSE 'FBM' END
)
SELECT
  COALESCE(s.day, r.day) AS day,
  COALESCE(s.fulfillment, r.fulfillment) AS fulfillment,
  COALESCE(s.units, 0)::integer AS units,
  round(COALESCE(s.gross_eur, 0) - COALESCE(s.vat_eur, 0), 4) AS net_revenue_eur,
  round(
    COALESCE(s.gross_eur, 0) - COALESCE(r.refund_amount_eur, 0)
    - (COALESCE(s.vat_eur, 0) - COALESCE(r.refund_vat_eur, 0))
    - (COALESCE(s.referral_eur, 0) - COALESCE(r.refund_referral_eur, 0))
    - COALESCE(s.fba_fee_eur, 0)
    - COALESCE(s.chargeback_eur, 0)
    - COALESCE(s.other_fee_eur, 0)
    - COALESCE(s.refund_commission_eur, 0)
    - COALESCE(s.fbm_shipping_eur, 0)
    - (COALESCE(s.cogs_eur, 0) - COALESCE(r.recovered_cogs_eur, 0))
    - COALESCE(r.return_fee_eur, 0)
  , 4) AS profit_eur
FROM sold s
FULL JOIN refunds r ON r.day = s.day AND r.fulfillment = s.fulfillment
WITH NO DATA;

CREATE UNIQUE INDEX mv_overview_fulfillment_daily_day_fulfillment_uidx
  ON product.mv_overview_fulfillment_daily USING btree (day, fulfillment);

CREATE MATERIALIZED VIEW "product"."mv_sales_analytics_daily" AS
SELECT
  purchase_day AS day,
  channel,
  store_key,
  COALESCE(sales_channel, '') AS sales_channel,
  sku,
  CASE WHEN fulfillment = 'FBA' THEN 'FBA' ELSE 'FBM' END AS fulfillment,
  COALESCE(NULLIF(btrim(ship_country::text), ''), '') AS ship_country,
  max(asin) AS asin,
  max(product_name) AS product_name,
  max(image_url) AS image_url,
  max(unit_cost_eur) AS unit_cost_eur,
  sum(quantity)::integer AS units,
  round(sum(gross_eur), 4) AS gross_eur,
  round(sum(vat_eur), 4) AS vat_eur,
  round(sum(customer_shipping_eur), 4) AS customer_shipping_eur,
  round(sum(customer_shipping_tax_eur), 4) AS customer_shipping_tax_eur,
  round(sum(referral_eur), 4) AS referral_eur,
  round(sum(digital_eur), 4) AS digital_eur,
  round(sum(fba_fee_eur), 4) AS fba_fee_eur,
  round(sum(chargeback_eur), 4) AS chargeback_eur,
  round(sum(other_fee_eur), 4) AS other_fee_eur,
  round(sum(refund_commission_eur), 4) AS refund_commission_eur,
  round(sum(fbm_shipping_eur), 4) AS fbm_shipping_eur,
  round(sum(cogs_eur), 4) AS cogs_eur,
  bool_or(has_fee_estimate) AS has_fee_estimate,
  COALESCE(sum(quantity) FILTER (WHERE cost_source = 'real'), 0)::integer AS real_cost_units,
  COALESCE(sum(quantity) FILTER (WHERE cost_source = 'provisional'), 0)::integer AS provisional_cost_units
FROM product.v_order_line_pnl p
WHERE is_sold
GROUP BY
  purchase_day,
  channel,
  store_key,
  COALESCE(sales_channel, ''),
  sku,
  CASE WHEN fulfillment = 'FBA' THEN 'FBA' ELSE 'FBM' END,
  COALESCE(NULLIF(btrim(ship_country::text), ''), '')
WITH NO DATA;

CREATE UNIQUE INDEX mv_sales_analytics_daily_grain_uidx
  ON product.mv_sales_analytics_daily USING btree (day, channel, store_key, sales_channel, sku, fulfillment, ship_country);
CREATE INDEX mv_sales_analytics_daily_day_idx
  ON product.mv_sales_analytics_daily USING btree (day);
CREATE INDEX mv_sales_analytics_daily_sku_day_idx
  ON product.mv_sales_analytics_daily USING btree (sku, day);

CREATE MATERIALIZED VIEW "product"."mv_sales_analytics_refund_daily" AS
SELECT
  refund_day AS day,
  channel,
  store_key,
  sku,
  sum(refund_units)::integer AS refund_units,
  round(sum(refund_amount_eur), 4) AS refund_amount_eur,
  round(sum(refund_vat_eur), 4) AS refund_vat_eur,
  round(sum(refund_referral_eur), 4) AS refund_referral_eur,
  sum(sellable_units)::integer AS sellable_units,
  round(sum(recovered_cogs_eur), 4) AS recovered_cogs_eur,
  round(sum(return_fee_eur), 4) AS return_fee_eur
FROM product.v_order_line_refund r
GROUP BY refund_day, channel, store_key, sku
WITH NO DATA;

CREATE UNIQUE INDEX mv_sales_analytics_refund_daily_grain_uidx
  ON product.mv_sales_analytics_refund_daily USING btree (day, channel, store_key, sku);
CREATE INDEX mv_sales_analytics_refund_daily_sku_day_idx
  ON product.mv_sales_analytics_refund_daily USING btree (sku, day);

CREATE MATERIALIZED VIEW "product"."mv_order_seasonality" AS
SELECT
  EXTRACT(year FROM o."purchaseDate")::integer AS year,
  EXTRACT(month FROM o."purchaseDate")::integer AS month,
  o.channel::text AS channel,
  o.sku,
  max(NULLIF(btrim(o.asin), '')) AS asin,
  max(NULLIF(btrim(o."productName"), '')) AS "productName",
  count(DISTINCT o."amazonOrderId") AS "orderCount",
  COALESCE(sum(o.quantity), 0)::bigint AS units,
  COALESCE(sum((
    COALESCE(o."itemPrice", 0) - COALESCE(o."itemPromotionDiscount", 0)
    + COALESCE(o."shippingPrice", 0) - COALESCE(o."shipPromotionDiscount", 0)
    + COALESCE(o."giftWrapPrice", 0)
  ) * CASE
    WHEN o.currency IS NULL OR btrim(o.currency) = '' OR upper(btrim(o.currency)) = 'EUR'
      OR fx.rate IS NULL OR fx.rate <= 0 THEN 1::numeric
    ELSE 1::numeric / fx.rate
  END), 0)::numeric(14, 2) AS revenue
FROM product."StoreOrderLine" o
LEFT JOIN product."ExchangeRate" fx
  ON fx.currency = upper(btrim(COALESCE(o.currency, 'EUR')))
 AND fx.base = 'EUR'
WHERE o."purchaseDate" IS NOT NULL
  AND btrim(o.sku) <> ''
  AND COALESCE(o.quantity, 0) > 0
  AND lower(btrim(COALESCE(o."itemStatus", '')))
    NOT IN ('cancelled', 'canceled', 'refunded', 'unfulfillable')
GROUP BY
  EXTRACT(year FROM o."purchaseDate")::integer,
  EXTRACT(month FROM o."purchaseDate")::integer,
  o.channel::text,
  o.sku
WITH NO DATA;

CREATE UNIQUE INDEX mv_order_seasonality_pk
  ON product.mv_order_seasonality USING btree (year, month, channel, sku);
CREATE INDEX mv_order_seasonality_channel_month
  ON product.mv_order_seasonality USING btree (channel, month);
CREATE INDEX mv_order_seasonality_sku
  ON product.mv_order_seasonality USING btree (sku);

REFRESH MATERIALIZED VIEW product.mv_overview_sales_daily;
REFRESH MATERIALIZED VIEW product.mv_overview_sku_daily;
REFRESH MATERIALIZED VIEW product.mv_overview_country_daily;
REFRESH MATERIALIZED VIEW product.mv_overview_fulfillment_daily;
REFRESH MATERIALIZED VIEW product.mv_sales_analytics_refund_daily;
REFRESH MATERIALIZED VIEW product.mv_sales_analytics_daily;
REFRESH MATERIALIZED VIEW product.mv_order_seasonality;
