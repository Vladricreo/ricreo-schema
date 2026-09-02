-- ============================================================================
-- Panoramica: conta anche gli ordini Amazon non ancora spediti.
--
-- v_order_line_pnl azzerava ricavo/costi se itemStatus <> Shipped. Gli ordini
-- Pending/Unshipped (tipici FBA/FBM degli ultimi giorni) sparivano dai grafici
-- e dai KPI. Ora is_sold include gli stati aperti; restano fuori Cancelled,
-- Refunded e Unfulfillable.
--
-- CREATE OR REPLACE: stesse colonne, le matview dipendenti restano valide.
-- Dopo il deploy: REFRESH delle mv_overview_* (e al prossimo cron anche
-- mv_sales_analytics_daily, che legge la stessa vista).
--
-- Applicabile anche via psql / Supabase CLI. Se lo fai fuori da Prisma:
--   bunx prisma migrate resolve --applied 20260902160000_overview_include_amazon_pending
-- ============================================================================

CREATE OR REPLACE VIEW "product"."v_order_line_pnl"
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
    -- Conteggia anche pending/unshipped: altrimenti gli ultimi giorni Amazon
    -- spariscono dalla panoramica finché l'ordine non viene spedito.
    (
      o."itemStatus" IS NULL
      OR btrim(o."itemStatus") = ''
      OR o."itemStatus" IN (
        'Shipped',
        'Unshipped',
        'Pending',
        'Shipping',
        'PartiallyShipped',
        'InvoiceUnconfirmed',
        'PendingAvailability'
      )
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
