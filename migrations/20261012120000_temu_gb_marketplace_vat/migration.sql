-- ============================================================================
-- Temu GB: IVA UK riscossa e versata da Temu (deemed supplier), come Amazon.
--
-- Confronto luglio/agosto 2026 con finance.report_temu: per GB il report Temu
-- è in GBP senza IVA (imposte 0), mentre noi tenevamo il lordo IVA inclusa e
-- mostravamo l'IVA UK come "IVA vendite" (modalità legacy). Il netto tornava,
-- ma lordo e IVA no. Ora Temu GB/CH/NO usa la modalità marketplace: IVA tolta
-- dal lordo, IVA = 0. Irlanda del Nord (CAP BT…) resta fuori, come per Amazon.
--
-- Unica modifica a product.order_line_amounts(): la riga TEMU in m.mode.
-- ============================================================================

-- Lordo e IVA di una riga ordine in valuta locale.
-- vat_mode: reported | marketplace | exempt | country_rate | none
--           | pass_through (eBay) | legacy (Etsy/Temu, regola precedente).
-- marketplace: Amazon e Temu verso GB/CH/NO (IVA del marketplace).
CREATE OR REPLACE FUNCTION product.order_line_amounts(
    o product."StoreOrderLine",
    dest TEXT,
    OUT gross_local NUMERIC,
    OUT shipping_local NUMERIC,
    OUT item_vat_local NUMERIC,
    OUT shipping_vat_local NUMERIC,
    OUT vat_local NUMERIC,
    OUT vat_mode TEXT
)
LANGUAGE sql
STABLE PARALLEL SAFE
AS $$
  WITH inv AS (
    SELECT
      COALESCE(ao."isBusinessOrder", false) OR ao."buyerTaxRegistrationType" IS NOT NULL AS is_business,
      ao."shipPostalCode" AS postal_code,
      ai."vatExclusiveItemPrice" AS vex_item,
      ai."vatExclusiveShippingPrice" AS vex_ship
    FROM inventory."AmazonOrder" ao
    LEFT JOIN inventory."AmazonOrderItem" ai
      ON ai."orderId" = ao.id
     AND (ai."orderItemId" = o."orderItemId" OR ai.sku = o.sku)
    WHERE o.channel = 'AMAZON'
      AND ao."amazonOrderId" = o."amazonOrderId"
    ORDER BY (ai."orderItemId" = o."orderItemId") DESC NULLS LAST, (ai.id IS NULL)
    LIMIT 1
  ),
  b AS (
    SELECT
      o.channel::text AS channel,
      upper(btrim(COALESCE(dest, ''))) AS dest,
      COALESCE(o."itemPrice", 0) - COALESCE(o."itemPromotionDiscount", 0) AS item_net,
      COALESCE(o."shippingPrice", 0) - COALESCE(o."shipPromotionDiscount", 0) AS ship_net,
      COALESCE(o."giftWrapPrice", 0) AS gift,
      GREATEST(COALESCE(o."itemTax", 0), 0) AS it,
      GREATEST(COALESCE(o."shippingTax", 0), 0) AS st,
      GREATEST(COALESCE(o."giftWrapTax", 0), 0) AS gt,
      COALESCE(inv.is_business, false) AS is_business,
      -- 0,00 vuol dire "non valorizzato" (spedizione gratuita, inventory vuoto).
      NULLIF(COALESCE(NULLIF(o."vatExclusiveItemPrice", 0), inv.vex_item), 0) AS vex_item,
      NULLIF(COALESCE(NULLIF(o."vatExclusiveShippingPrice", 0), inv.vex_ship), 0) AS vex_ship,
      upper(COALESCE(o."shipPostalCode", inv.postal_code, '')) LIKE 'BT%' AS northern_ireland,
      lower(btrim(COALESCE(o."itemStatus", ''))) IN ('', 'pending', 'unshipped', 'pendingavailability') AS pending,
      -- Marketplace UE dove Amazon non calcola l'IVA (niente VCS).
      lower(btrim(COALESCE(o."salesChannel", ''))) IN ('amazon.ie') AS no_vcs
    FROM (SELECT 1) one
    LEFT JOIN inv ON true
  ),
  d AS (
    SELECT
      b.*,
      b.item_net + b.ship_net + b.gift AS gross_incl,
      b.it + b.st + b.gt AS reported,
      CASE WHEN b.vex_item IS NOT NULL AND b.item_net > 0
        THEN LEAST(b.item_net, GREATEST(0, o."itemPrice" - b.vex_item)) ELSE 0 END AS d_item,
      CASE WHEN b.vex_ship IS NOT NULL AND b.ship_net > 0
        THEN LEAST(b.ship_net, GREATEST(0, o."shippingPrice" - b.vex_ship)) ELSE 0 END AS d_ship,
      product.eu_vat_rate(b.dest) AS rate
    FROM b
  ),
  m AS (
    SELECT
      d.*,
      CASE
        WHEN d.channel = 'EBAY' THEN 'pass_through'
        -- Temu UK: deemed supplier, l'IVA la versa Temu (report fiscale: imposte 0).
        WHEN d.channel = 'TEMU' AND d.dest IN ('GB', 'CH', 'NO') AND NOT d.northern_ireland THEN 'marketplace'
        WHEN d.channel <> 'AMAZON' THEN 'legacy'
        WHEN d.dest IN ('GB', 'CH', 'NO') AND NOT d.northern_ireland THEN 'marketplace'
        WHEN d.reported > 0 THEN 'reported'
        WHEN d.d_item + d.d_ship > 0.01 OR d.is_business THEN 'exempt'
        WHEN d.rate > 0 AND d.gross_incl > 0 AND (d.pending OR d.no_vcs) THEN 'country_rate'
        WHEN d.rate > 0 THEN 'exempt'
        ELSE 'none'
      END AS mode
    FROM d
  ),
  r AS (
    SELECT
      m.*,
      CASE m.mode
        WHEN 'legacy' THEN
          COALESCE(NULLIF(o."itemTax", 0), GREATEST(0, o."itemPrice" - o."vatExclusiveItemPrice"), 0)
          + COALESCE(o."giftWrapTax", 0)
        WHEN 'reported' THEN (CASE WHEN m.it > 0 THEN m.it ELSE m.d_item END) + m.gt
        WHEN 'country_rate' THEN round((m.item_net + m.gift) - (m.item_net + m.gift) / (1 + m.rate), 2)
        ELSE 0
      END AS item_vat,
      CASE m.mode
        WHEN 'legacy' THEN
          COALESCE(NULLIF(o."shippingTax", 0), GREATEST(0, o."shippingPrice" - o."vatExclusiveShippingPrice"), 0)
        WHEN 'reported' THEN CASE WHEN m.st > 0 THEN m.st ELSE m.d_ship END
        WHEN 'country_rate' THEN round(m.ship_net - m.ship_net / (1 + m.rate), 2)
        ELSE 0
      END AS ship_vat
    FROM m
  )
  SELECT
    CASE r.mode
      WHEN 'marketplace' THEN r.gross_incl - r.reported
      WHEN 'exempt' THEN r.gross_incl - r.d_item - r.d_ship
      ELSE r.gross_incl
    END,
    CASE r.mode
      WHEN 'marketplace' THEN r.ship_net - r.st
      WHEN 'exempt' THEN r.ship_net - r.d_ship
      ELSE r.ship_net
    END,
    r.item_vat,
    r.ship_vat,
    r.item_vat + r.ship_vat,
    r.mode
  FROM r
$$;

REFRESH MATERIALIZED VIEW product.mv_overview_sales_daily;
REFRESH MATERIALIZED VIEW product.mv_overview_sku_daily;
