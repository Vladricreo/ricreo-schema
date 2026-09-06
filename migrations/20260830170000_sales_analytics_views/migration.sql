-- ============================================================================
-- Vendite (dashboard/sales-analytics): P&L per riga ordine + matview giornaliere.
--
-- Tre cose che questa migration mette a posto:
--
-- 1. COSTI REALI vs PROVVISORI. v_order_line_pnl è nata due giorni prima di
--    20260830160000_store_order_fee_provisional_costs e sceglieva ancora fee
--    reale e stima componente per componente (COALESCE(NULLIF(reale,0), stima)).
--    Ora la regola è quella di src/lib/amazon-sales/fee-sql.ts: la riga fee si
--    sceglie preferendo realCosts, e ogni voce è `reale` se realCosts, altrimenti
--    la colonna `provisional*`. Niente più mix delle due fonti sullo stesso ordine.
--
-- 2. SPEDIZIONE PAGATA DAL CLIENTE. shippingPrice - shipPromotionDiscount entra
--    nel lordo (ed è esposta anche da sola in customer_shipping_eur), shippingTax
--    entra nell'IVA. Su FBA Amazon la trattiene: è chargeback_eur, reale da
--    Finances o provvisorio (spedizione cliente / 1.22). Su FBM il costo è la
--    quota dell'etichetta reale, altrimenti provisionalFbmShipping.
--
-- 3. DOPPIO CONTEGGIO DELLA DIGITAL SERVICES FEE. referralFee include già la DSF
--    (finances.ts: DigitalServicesFee sta in REFERRAL_FEE_TYPES; provisional-costs.ts
--    la ricava come 3/103 del referral lordo). Le matview overview sottraevano
--    referral_eur E digital_eur, contando la DSF due volte. Ora digital_eur resta
--    solo come dettaglio informativo e non viene più sottratta.
--
-- Applicabile anche via psql / Supabase CLI. Se lo fai fuori da Prisma:
--   bunx prisma migrate resolve --applied 20260830170000_sales_analytics_views
-- ============================================================================

DROP MATERIALIZED VIEW IF EXISTS "product"."mv_sales_analytics_refund_daily";
DROP MATERIALIZED VIEW IF EXISTS "product"."mv_sales_analytics_daily";
DROP MATERIALIZED VIEW IF EXISTS "product"."mv_overview_country_daily";
DROP MATERIALIZED VIEW IF EXISTS "product"."mv_overview_fulfillment_daily";
DROP MATERIALIZED VIEW IF EXISTS "product"."mv_overview_sku_daily";
DROP MATERIALIZED VIEW IF EXISTS "product"."mv_overview_sales_daily";
DROP VIEW IF EXISTS "product"."v_order_line_refund";
DROP VIEW IF EXISTS "product"."v_order_line_pnl";

-- ---------------------------------------------------------------------------
-- P&L di ogni riga StoreOrderLine, importi in EUR.
-- ---------------------------------------------------------------------------
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
  -- Commissione di vendita LORDA: include già la DSF, non sommarci digital_eur.
  CASE WHEN line.is_sold THEN ROUND(line.referral_local * line.eur_factor, 4) ELSE 0 END AS referral_eur,
  -- Solo dettaglio: quota DSF già compresa in referral_eur.
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
  line.has_fee_estimate,
  -- Colonne aggiunte per la pagina vendite.
  line.sales_channel,
  line.order_item_id,
  -- Spedizione incassata dal cliente (al netto dello sconto spedizione).
  CASE WHEN line.is_sold THEN ROUND(line.customer_shipping_local * line.eur_factor, 4) ELSE 0 END AS customer_shipping_eur,
  CASE WHEN line.is_sold THEN ROUND(line.customer_shipping_tax_local * line.eur_factor, 4) ELSE 0 END AS customer_shipping_tax_eur,
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
    -- Lordo incassato: merce + spedizione cliente, sconti già tolti.
    (
      COALESCE(o."itemPrice", 0)
      - COALESCE(o."itemPromotionDiscount", 0)
      + COALESCE(o."shippingPrice", 0)
      - COALESCE(o."shipPromotionDiscount", 0)
    ) AS gross_local,
    (COALESCE(o."itemTax", 0) + COALESCE(o."shippingTax", 0)) AS vat_local,
    (
      COALESCE(o."shippingPrice", 0)
      - COALESCE(o."shipPromotionDiscount", 0)
    ) AS customer_shipping_local,
    COALESCE(o."shippingTax", 0) AS customer_shipping_tax_local,
    CASE
      WHEN o.currency IS NULL
        OR btrim(o.currency) = ''
        OR UPPER(btrim(o.currency)) = 'EUR'
        OR fx.rate IS NULL
        OR fx.rate <= 0
      THEN 1::numeric
      ELSE 1 / fx.rate
    END AS eur_factor,
    -- Reale se la riga fee è saldata, altrimenti la stima persistita.
    COALESCE(
      CASE
        WHEN fee."realCosts" THEN fee."referralFee"
        ELSE fee."provisionalReferralFee"
      END,
      0
    ) AS referral_local,
    COALESCE(
      CASE
        WHEN fee."realCosts" THEN fee."digitalServicesFee"
        ELSE fee."provisionalDigitalServicesFee"
      END,
      0
    ) AS digital_local,
    CASE
      WHEN o."fulfillmentChannel" = 'FBA' THEN
        COALESCE(
          CASE
            WHEN fee."realCosts" THEN fee."fbaFulfillmentFee"
            ELSE fee."provisionalFbaFee"
          END,
          0
        )
      ELSE 0
    END AS fba_fee_local,
    -- Storno spedizione: Amazon trattiene quella addebitata al cliente.
    CASE
      WHEN o."fulfillmentChannel" = 'FBA' THEN
        COALESCE(
          CASE
            WHEN fee."realCosts" THEN fee."shippingChargeback"
            ELSE fee."provisionalShippingChargeback"
          END,
          0
        )
      ELSE 0
    END AS chargeback_local,
    COALESCE(NULLIF(fee."otherFee", 0), 0) AS other_fee_local,
    COALESCE(NULLIF(fee."refundCommission", 0), 0) AS refund_commission_local,
    -- FBM: quota dell'etichetta reale, altrimenti la stima persistita.
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
      ELSE COALESCE(fee."provisionalFbmShipping", 0)
    END AS fbm_shipping_eur,
    CASE
      WHEN o."fulfillmentChannel" = 'FBA' THEN 'amazon'
      WHEN NOT (
        o."fulfillmentChannel" = 'FBM'
        OR (
          o.channel::text IS DISTINCT FROM 'AMAZON'
          AND (o."fulfillmentChannel" IS NULL OR btrim(o."fulfillmentChannel") = '')
        )
      ) THEN 'none'
      WHEN inv_ship.unit_cost IS NOT NULL THEN 'shipment'
      WHEN fee."provisionalShippingSource" = 'shipping_price' THEN 'default'
      WHEN fee."provisionalShippingSource" = 'shipping_average' THEN 'average'
      WHEN COALESCE(fee."provisionalFbmShipping", 0) > 0 THEN 'default'
      ELSE 'none'
    END AS fbm_shipping_source,
    CASE
      WHEN fee."realCosts" THEN 'real'
      WHEN fee."provisionalAt" IS NOT NULL THEN 'provisional'
      ELSE 'none'
    END AS cost_source,
    (
      COALESCE(fee."realCosts", false)
      OR COALESCE(fee."provisionalReferralFee", 0) > 0
      OR COALESCE(fee."provisionalFbaFee", 0) > 0
      OR COALESCE(fee."referralFee", 0) > 0
      OR COALESCE(fee."fbaFulfillmentFee", 0) > 0
      OR COALESCE(fee."otherFee", 0) > 0
    ) AS has_fee_estimate
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
        (sf."orderItemId" <> '' AND sf."orderItemId" = COALESCE(o."orderItemId", ''))
        OR sf.sku = o.sku
      )
    ORDER BY
      CASE WHEN sf."realCosts" THEN 0 ELSE 1 END,
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
  LEFT JOIN product."ExchangeRate" fx
    ON fx.currency = UPPER(btrim(COALESCE(o.currency, 'EUR')))
    AND fx.base = 'EUR'
  WHERE o."purchaseDate" IS NOT NULL
) line
LEFT JOIN "product"."mv_overview_sku_meta" meta ON meta.sku = line.sku;

-- ---------------------------------------------------------------------------
-- Resi imputati alla data di reso, con importi dalla riga ordine originale.
-- ---------------------------------------------------------------------------
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
    WHEN r.is_sellable AND o.unit_cost_eur IS NOT NULL
      THEN ROUND(o.unit_cost_eur * r.quantity, 4)
    ELSE 0
  END AS recovered_cogs_eur,
  ROUND(r.quantity * COALESCE(NULLIF(est."fbaFeeDomestic", 0), 3.5), 4) AS return_fee_eur,
  -- Colonne aggiunte per la pagina vendite.
  r."storeKey" AS store_key,
  CASE WHEN r.is_sellable THEN r.quantity ELSE 0 END AS sellable_units
FROM (
  SELECT DISTINCT ON (r.channel, COALESCE(r."amazonOrderId", r.id::text), r.sku)
    r.*,
    (
      r.status IS DISTINCT FROM 'FINANCES'
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
    ) AS is_sellable
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

-- ---------------------------------------------------------------------------
-- Panoramica: aggregato giorno × canale (finestra 730 giorni).
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- Panoramica: aggregato giorno × canale × SKU (finestra 730 giorni).
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- Panoramica: FBA vs FBM per giorno (finestra 730 giorni).
-- ---------------------------------------------------------------------------
CREATE MATERIALIZED VIEW "product"."mv_overview_fulfillment_daily" AS
SELECT
  p.purchase_day AS day,
  CASE WHEN p.fulfillment = 'FBA' THEN 'FBA' ELSE 'FBM' END AS fulfillment,
  SUM(p.quantity)::int AS units,
  ROUND(SUM(p.gross_eur - p.vat_eur), 4) AS net_revenue_eur,
  ROUND(
    SUM(
      p.gross_eur
      - p.vat_eur
      - p.referral_eur
      - p.fba_fee_eur
      - p.chargeback_eur
      - p.other_fee_eur
      - p.refund_commission_eur
      - p.fbm_shipping_eur
      - p.cogs_eur
    ),
    4
  ) AS profit_eur
FROM "product"."v_order_line_pnl" p
WHERE p.is_sold
  AND p.purchase_day >= CURRENT_DATE - INTERVAL '730 days'
GROUP BY p.purchase_day, CASE WHEN p.fulfillment = 'FBA' THEN 'FBA' ELSE 'FBM' END;

CREATE UNIQUE INDEX "mv_overview_fulfillment_daily_day_fulfillment_uidx"
  ON "product"."mv_overview_fulfillment_daily" (day, fulfillment);

-- ---------------------------------------------------------------------------
-- Panoramica: paese di destinazione per giorno (finestra 730 giorni).
-- ---------------------------------------------------------------------------
CREATE MATERIALIZED VIEW "product"."mv_overview_country_daily" AS
SELECT
  p.purchase_day AS day,
  COALESCE(NULLIF(btrim(p.ship_country), ''), 'XX') AS country_code,
  SUM(p.quantity)::int AS units,
  ROUND(SUM(p.gross_eur - p.vat_eur), 4) AS net_revenue_eur,
  ROUND(
    SUM(
      p.gross_eur
      - p.vat_eur
      - p.referral_eur
      - p.fba_fee_eur
      - p.chargeback_eur
      - p.other_fee_eur
      - p.refund_commission_eur
      - p.fbm_shipping_eur
      - p.cogs_eur
    ),
    4
  ) AS profit_eur
FROM "product"."v_order_line_pnl" p
WHERE p.is_sold
  AND p.purchase_day >= CURRENT_DATE - INTERVAL '730 days'
GROUP BY p.purchase_day, COALESCE(NULLIF(btrim(p.ship_country), ''), 'XX');

CREATE UNIQUE INDEX "mv_overview_country_daily_day_country_uidx"
  ON "product"."mv_overview_country_daily" (day, country_code);

-- ---------------------------------------------------------------------------
-- Vendite: grana giornaliera per la lista /dashboard/sales-analytics.
--
-- La lista filtra per periodo arbitrario (anche "tutto"), canale, store e
-- fulfillment, e confronta col periodo precedente: la grana tiene tutte le
-- dimensioni filtrabili in chiave, così l'app fa solo GROUP BY sku.
-- Nessuna finestra temporale: il filtro "tutto" deve restare esatto.
--
-- Le colonne monetarie sono additive: il profitto si compone a valle
-- (src/features/sales-analytics/lib/profit.ts) perché dipende da politiche
-- per canale (Temu) e dal COGS recuperato sui resi vendibili.
-- ---------------------------------------------------------------------------
CREATE MATERIALIZED VIEW "product"."mv_sales_analytics_daily" AS
SELECT
  p.purchase_day AS day,
  p.channel,
  p.store_key,
  COALESCE(p.sales_channel, '') AS sales_channel,
  p.sku,
  CASE WHEN p.fulfillment = 'FBA' THEN 'FBA' ELSE 'FBM' END AS fulfillment,
  COALESCE(NULLIF(btrim(p.ship_country), ''), '') AS ship_country,
  MAX(p.asin) AS asin,
  MAX(p.product_name) AS product_name,
  MAX(p.image_url) AS image_url,
  MAX(p.unit_cost_eur) AS unit_cost_eur,
  SUM(p.quantity)::int AS units,
  ROUND(SUM(p.gross_eur), 4) AS gross_eur,
  ROUND(SUM(p.vat_eur), 4) AS vat_eur,
  ROUND(SUM(p.customer_shipping_eur), 4) AS customer_shipping_eur,
  ROUND(SUM(p.customer_shipping_tax_eur), 4) AS customer_shipping_tax_eur,
  ROUND(SUM(p.referral_eur), 4) AS referral_eur,
  ROUND(SUM(p.digital_eur), 4) AS digital_eur,
  ROUND(SUM(p.fba_fee_eur), 4) AS fba_fee_eur,
  ROUND(SUM(p.chargeback_eur), 4) AS chargeback_eur,
  ROUND(SUM(p.other_fee_eur), 4) AS other_fee_eur,
  ROUND(SUM(p.refund_commission_eur), 4) AS refund_commission_eur,
  ROUND(SUM(p.fbm_shipping_eur), 4) AS fbm_shipping_eur,
  ROUND(SUM(p.cogs_eur), 4) AS cogs_eur,
  BOOL_OR(p.has_fee_estimate) AS has_fee_estimate,
  COALESCE(SUM(p.quantity) FILTER (WHERE p.cost_source = 'real'), 0)::int AS real_cost_units,
  COALESCE(SUM(p.quantity) FILTER (WHERE p.cost_source = 'provisional'), 0)::int AS provisional_cost_units
FROM "product"."v_order_line_pnl" p
WHERE p.is_sold
GROUP BY
  p.purchase_day,
  p.channel,
  p.store_key,
  COALESCE(p.sales_channel, ''),
  p.sku,
  CASE WHEN p.fulfillment = 'FBA' THEN 'FBA' ELSE 'FBM' END,
  COALESCE(NULLIF(btrim(p.ship_country), ''), '');

-- Serve a REFRESH ... CONCURRENTLY: nessuna colonna in chiave può essere NULL.
CREATE UNIQUE INDEX "mv_sales_analytics_daily_grain_uidx"
  ON "product"."mv_sales_analytics_daily"
  (day, channel, store_key, sales_channel, sku, fulfillment, ship_country);

CREATE INDEX "mv_sales_analytics_daily_sku_day_idx"
  ON "product"."mv_sales_analytics_daily" (sku, day);

CREATE INDEX "mv_sales_analytics_daily_day_idx"
  ON "product"."mv_sales_analytics_daily" (day);

-- ---------------------------------------------------------------------------
-- Vendite: resi per giorno di reso, stessa grana filtrabile della lista.
-- ---------------------------------------------------------------------------
CREATE MATERIALIZED VIEW "product"."mv_sales_analytics_refund_daily" AS
SELECT
  r.refund_day AS day,
  r.channel,
  r.store_key,
  r.sku,
  SUM(r.refund_units)::int AS refund_units,
  ROUND(SUM(r.refund_amount_eur), 4) AS refund_amount_eur,
  ROUND(SUM(r.refund_vat_eur), 4) AS refund_vat_eur,
  ROUND(SUM(r.refund_referral_eur), 4) AS refund_referral_eur,
  SUM(r.sellable_units)::int AS sellable_units,
  ROUND(SUM(r.recovered_cogs_eur), 4) AS recovered_cogs_eur,
  ROUND(SUM(r.return_fee_eur), 4) AS return_fee_eur
FROM "product"."v_order_line_refund" r
GROUP BY r.refund_day, r.channel, r.store_key, r.sku;

CREATE UNIQUE INDEX "mv_sales_analytics_refund_daily_grain_uidx"
  ON "product"."mv_sales_analytics_refund_daily" (day, channel, store_key, sku);

CREATE INDEX "mv_sales_analytics_refund_daily_sku_day_idx"
  ON "product"."mv_sales_analytics_refund_daily" (sku, day);
