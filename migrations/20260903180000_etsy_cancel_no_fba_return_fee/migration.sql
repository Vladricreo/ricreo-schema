-- ============================================================================
-- Fee reso FBA solo su Amazon FBA.
--
-- v_order_line_refund applicava 3.50 € (o Fee Preview) a ogni reso,
-- anche Etsy/eBay/Temu. Gli annulli Etsy diventavano perdite fittizie
-- su overview e sales-analytics.
-- ============================================================================

CREATE OR REPLACE VIEW "product"."v_order_line_refund"
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
  CASE
    WHEN r.channel = 'AMAZON'
      AND (
        o.fulfillment = 'FBA'
        OR UPPER(btrim(COALESCE(r."amazonFulfillment", ''))) = 'FBA'
      )
      THEN ROUND(r.quantity * COALESCE(NULLIF(est."fbaFeeDomestic", 0), 3.5), 4)
    ELSE 0
  END AS return_fee_eur,
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
    p.unit_cost_eur,
    p.fulfillment
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
