-- ============================================================================
-- Lordo / IVA / netto Amazon allineati a ZonWizard + cambio del giorno.
--
-- Confronto agosto 2026 con finance.transazioni (ZonWizard) ha mostrato:
--   1. GB / CH / NO: l'IVA la riscuote e versa Amazon (marketplace deemed
--      supplier). Non è IVA nostra: va tolta dal lordo, IVA = 0.
--      Eccezione Irlanda del Nord (CAP BT…): regime UE, l'IVA è nostra.
--   2. Esente (B2B VIES / reverse charge / export): item-tax vuoto su ordine
--      spedito. Amazon calcola l'IVA (VCS) su tutti i marketplace UE salvo
--      Amazon.ie: se non l'ha messa, non c'è. Se vat-exclusive < item-price il
--      cliente ha pagato il prezzo senza IVA: lordo = vat-exclusive. Prima la
--      differenza veniva contata come IVA da versare.
--   3. Stima con l'aliquota del paese di destinazione solo dove Amazon non
--      calcola l'IVA (Amazon.ie) o l'ordine non è ancora spedito (item-tax
--      arriva alla spedizione).
--   4. Valute: si usava l'ultimo tasso per tutto lo storico. Ora storico
--      giornaliero (ExchangeRateDaily) e tasso del giorno d'acquisto.
--
-- product.order_line_amounts() è l'unica fonte delle regole: la usano
-- v_order_line_pnl, la tabella Ordini e i KPI vendite.
-- inventory.AmazonOrder / AmazonOrderItem sono solo lette (flag business,
-- vat-exclusive mancante nel report ordini).
-- ============================================================================

CREATE TABLE IF NOT EXISTS product."ExchangeRateDaily" (
    currency TEXT NOT NULL,
    base TEXT NOT NULL DEFAULT 'EUR',
    "rateDate" DATE NOT NULL,
    rate DECIMAL(18,8) NOT NULL,
    source TEXT NOT NULL DEFAULT 'frankfurter',
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,
    CONSTRAINT "ExchangeRateDaily_pkey" PRIMARY KEY (currency, "rateDate")
);

-- Seme: l'ultimo tasso già in archivio (lo storico lo scarica il cron).
INSERT INTO product."ExchangeRateDaily" (currency, base, "rateDate", rate, source, "updatedAt")
SELECT currency, base, "rateDate", rate, source, now()
FROM product."ExchangeRate"
WHERE base = 'EUR'
ON CONFLICT (currency, "rateDate") DO NOTHING;

-- Aliquota IVA ordinaria UE-27 (stessa tabella di src/lib/vat/eu-standard-rates.ts).
CREATE OR REPLACE FUNCTION product.eu_vat_rate(country TEXT)
RETURNS NUMERIC
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
AS $$
  SELECT CASE upper(btrim(COALESCE(country, '')))
    WHEN 'AT' THEN 0.20 WHEN 'BE' THEN 0.21 WHEN 'BG' THEN 0.20 WHEN 'HR' THEN 0.25
    WHEN 'CY' THEN 0.19 WHEN 'CZ' THEN 0.21 WHEN 'DK' THEN 0.25 WHEN 'EE' THEN 0.24
    WHEN 'FI' THEN 0.255 WHEN 'FR' THEN 0.20 WHEN 'DE' THEN 0.19 WHEN 'GR' THEN 0.24
    WHEN 'HU' THEN 0.27 WHEN 'IE' THEN 0.23 WHEN 'IT' THEN 0.22 WHEN 'LV' THEN 0.21
    WHEN 'LT' THEN 0.21 WHEN 'LU' THEN 0.17 WHEN 'MT' THEN 0.18 WHEN 'NL' THEN 0.21
    WHEN 'PL' THEN 0.23 WHEN 'PT' THEN 0.23 WHEN 'RO' THEN 0.21 WHEN 'SK' THEN 0.23
    WHEN 'SI' THEN 0.22 WHEN 'ES' THEN 0.21 WHEN 'SE' THEN 0.25
    ELSE 0
  END::numeric
$$;

-- Fattore verso EUR al giorno indicato: ultimo tasso ≤ giorno, poi il primo
-- successivo, poi l'ultimo noto. 1 per EUR o valuta senza tasso.
CREATE OR REPLACE FUNCTION product.eur_factor(currency TEXT, day DATE)
RETURNS NUMERIC
LANGUAGE sql
STABLE PARALLEL SAFE
AS $$
  SELECT CASE
    WHEN currency IS NULL OR btrim(currency) = '' OR upper(btrim(currency)) = 'EUR' THEN 1::numeric
    ELSE COALESCE(1::numeric / NULLIF(COALESCE(
      (SELECT d.rate FROM product."ExchangeRateDaily" d
        WHERE d.currency = upper(btrim(eur_factor.currency)) AND d.base = 'EUR' AND d."rateDate" <= day
        ORDER BY d."rateDate" DESC LIMIT 1),
      (SELECT d.rate FROM product."ExchangeRateDaily" d
        WHERE d.currency = upper(btrim(eur_factor.currency)) AND d.base = 'EUR' AND d."rateDate" > day
        ORDER BY d."rateDate" ASC LIMIT 1),
      (SELECT fx.rate FROM product."ExchangeRate" fx
        WHERE fx.currency = upper(btrim(eur_factor.currency)) AND fx.base = 'EUR' LIMIT 1)
    ), 0), 1::numeric)
  END
$$;

-- Lordo e IVA di una riga ordine in valuta locale.
-- vat_mode: reported | marketplace | exempt | country_rate | none
--           | pass_through (eBay) | legacy (Etsy/Temu, regola precedente).
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

CREATE OR REPLACE VIEW product.v_order_line_pnl AS
SELECT line.channel,
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
            ELSE COALESCE(NULLIF(btrim(line.fulfillment_channel), ''::text), 'FBM'::text)
        END AS fulfillment,
    line.is_sold,
    line.quantity,
        CASE
            WHEN line.is_sold THEN round(line.gross_local * line.eur_factor, 4)
            ELSE 0::numeric
        END AS gross_eur,
        CASE
            WHEN line.is_sold THEN round(line.vat_local * line.eur_factor, 4)
            ELSE 0::numeric
        END AS vat_eur,
        CASE
            WHEN line.is_sold THEN round(line.referral_local * line.eur_factor, 4)
            ELSE 0::numeric
        END AS referral_eur,
        CASE
            WHEN line.is_sold THEN round(line.digital_local * line.eur_factor, 4)
            ELSE 0::numeric
        END AS digital_eur,
        CASE
            WHEN line.is_sold THEN round(line.fba_fee_local * line.eur_factor, 4)
            ELSE 0::numeric
        END AS fba_fee_eur,
        CASE
            WHEN line.is_sold THEN round(line.chargeback_local * line.eur_factor, 4)
            ELSE 0::numeric
        END AS chargeback_eur,
        CASE
            WHEN line.is_sold THEN round(line.other_fee_local * line.eur_factor, 4)
            ELSE 0::numeric
        END AS other_fee_eur,
        CASE
            WHEN line.is_sold THEN round(line.refund_commission_local * line.eur_factor, 4)
            ELSE 0::numeric
        END AS refund_commission_eur,
        CASE
            WHEN line.is_sold THEN round(line.fbm_shipping_eur, 4)
            ELSE 0::numeric
        END AS fbm_shipping_eur,
    meta.unit_cost_eur,
        CASE
            WHEN line.is_sold AND meta.unit_cost_eur IS NOT NULL THEN round(meta.unit_cost_eur * GREATEST(line.quantity, 0)::numeric, 4)
            ELSE 0::numeric
        END AS cogs_eur,
    line.has_fee_estimate,
    line.sales_channel,
    line.order_item_id,
        CASE
            WHEN line.is_sold THEN round(line.customer_shipping_local * line.eur_factor, 4)
            ELSE 0::numeric
        END AS customer_shipping_eur,
        CASE
            WHEN line.is_sold THEN round(line.customer_shipping_tax_local * line.eur_factor, 4)
            ELSE 0::numeric
        END AS customer_shipping_tax_eur,
    line.cost_source,
    line.fbm_shipping_source,
    meta.image_url,
    line.vat_mode
   FROM ( SELECT o.channel::text AS channel,
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
            (lower(btrim(COALESCE(o."itemStatus", ''::text))) <> ALL (ARRAY['cancelled'::text, 'canceled'::text, 'refunded'::text, 'unfulfillable'::text])) AND COALESCE(o.quantity, 0) > 0 AND (COALESCE(o."itemPrice", 0::numeric) - COALESCE(o."itemPromotionDiscount", 0::numeric) + COALESCE(o."shippingPrice", 0::numeric) - COALESCE(o."shipPromotionDiscount", 0::numeric) + COALESCE(o."giftWrapPrice", 0::numeric)) > 0::numeric AS is_sold,
            o."fulfillmentChannel" = 'FBA'::text AS is_fba,
            o."fulfillmentChannel" = 'FBM'::text OR o.channel::text IS DISTINCT FROM 'AMAZON'::text AND (o."fulfillmentChannel" IS NULL OR btrim(o."fulfillmentChannel") = ''::text) AS is_fbm,
            dest.country AS dest_country,
            amt.gross_local,
            amt.vat_local,
            amt.shipping_local AS customer_shipping_local,
            amt.shipping_vat_local AS customer_shipping_tax_local,
            amt.vat_mode,
            product.eur_factor(o.currency, o."purchaseDate"::date) AS eur_factor,
            COALESCE(
                CASE
                    WHEN fee."realCosts" THEN fee."referralFee"
                    ELSE fee."provisionalReferralFee"
                END, 0::numeric) AS referral_local,
            COALESCE(
                CASE
                    WHEN fee."realCosts" THEN fee."digitalServicesFee"
                    ELSE fee."provisionalDigitalServicesFee"
                END, 0::numeric) AS digital_local,
                CASE
                    WHEN o."fulfillmentChannel" = 'FBA'::text THEN COALESCE(
                    CASE
                        WHEN fee."realCosts" THEN fee."fbaFulfillmentFee"
                        ELSE fee."provisionalFbaFee"
                    END, 0::numeric)
                    ELSE 0::numeric
                END AS fba_fee_local,
                CASE
                    WHEN o."fulfillmentChannel" = 'FBA'::text THEN COALESCE(
                    CASE
                        WHEN fee."realCosts" THEN fee."shippingChargeback"
                        ELSE fee."provisionalShippingChargeback"
                    END, 0::numeric)
                    ELSE 0::numeric
                END AS chargeback_local,
            COALESCE(NULLIF(fee."otherFee", 0::numeric), 0::numeric) AS other_fee_local,
            COALESCE(NULLIF(fee."refundCommission", 0::numeric), 0::numeric) AS refund_commission_local,
                CASE
                    WHEN o."fulfillmentChannel" = 'FBA'::text THEN 0::numeric
                    WHEN NOT (o."fulfillmentChannel" = 'FBM'::text OR o.channel::text IS DISTINCT FROM 'AMAZON'::text AND (o."fulfillmentChannel" IS NULL OR btrim(o."fulfillmentChannel") = ''::text)) THEN 0::numeric
                    WHEN inv_ship.unit_cost IS NOT NULL THEN inv_ship.unit_cost * GREATEST(o.quantity, 0)::numeric
                    ELSE COALESCE(fee."provisionalFbmShipping", 0::numeric)
                END AS fbm_shipping_eur,
                CASE
                    WHEN o."fulfillmentChannel" = 'FBA'::text THEN 'amazon'::text
                    WHEN NOT (o."fulfillmentChannel" = 'FBM'::text OR o.channel::text IS DISTINCT FROM 'AMAZON'::text AND (o."fulfillmentChannel" IS NULL OR btrim(o."fulfillmentChannel") = ''::text)) THEN 'none'::text
                    WHEN inv_ship.unit_cost IS NOT NULL THEN 'shipment'::text
                    WHEN fee."provisionalShippingSource" = 'shipping_price'::text THEN 'default'::text
                    WHEN fee."provisionalShippingSource" = 'shipping_average'::text THEN 'average'::text
                    WHEN COALESCE(fee."provisionalFbmShipping", 0::numeric) > 0::numeric THEN 'default'::text
                    ELSE 'none'::text
                END AS fbm_shipping_source,
                CASE
                    WHEN fee."realCosts" THEN 'real'::text
                    WHEN fee."provisionalAt" IS NOT NULL THEN 'provisional'::text
                    ELSE 'none'::text
                END AS cost_source,
            COALESCE(fee."realCosts", false) OR COALESCE(fee."provisionalReferralFee", 0::numeric) > 0::numeric OR COALESCE(fee."provisionalFbaFee", 0::numeric) > 0::numeric OR COALESCE(fee."referralFee", 0::numeric) > 0::numeric OR COALESCE(fee."fbaFulfillmentFee", 0::numeric) > 0::numeric OR COALESCE(fee."otherFee", 0::numeric) > 0::numeric AS has_fee_estimate
           FROM product."StoreOrderLine" o
             LEFT JOIN LATERAL ( SELECT sf."fbaFulfillmentFee",
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
                  WHERE sf.channel = o.channel AND sf."amazonOrderId" = o."amazonOrderId" AND (sf."orderItemId" <> ''::text AND sf."orderItemId" = COALESCE(o."orderItemId", ''::text) OR sf.sku = o.sku)
                  ORDER BY (
                        CASE
                            WHEN sf."realCosts" THEN 0
                            ELSE 1
                        END), (
                        CASE
                            WHEN sf."orderItemId" <> ''::text AND sf."orderItemId" = COALESCE(o."orderItemId", ''::text) THEN 0
                            ELSE 1
                        END), (
                        CASE
                            WHEN sf.sku = o.sku THEN 0
                            ELSE 1
                        END)
                 LIMIT 1) fee ON true
             LEFT JOIN LATERAL ( SELECT
                        CASE
                            WHEN s."shippingCost" IS NOT NULL AND s."shippingCost" > 0::numeric AND qty.total_qty > 0 THEN s."shippingCost" / qty.total_qty::numeric
                            ELSE NULL::numeric
                        END AS unit_cost,
                    s."recipientCountry" AS recipient_country
                   FROM inventory."Shipment" s
                     JOIN LATERAL ( SELECT COALESCE(sum(GREATEST(l.quantity, 0)), 0::bigint) AS total_qty
                           FROM inventory."ShipmentLine" l
                          WHERE l."shipmentId" = s.id) qty ON true
                  WHERE o."amazonOrderId" IS NOT NULL AND btrim(o."amazonOrderId") <> ''::text AND s."shipmentType" IS DISTINCT FROM 'FBA'::inventory."ShipmentType" AND (s."marketplaceOrderId" = o."amazonOrderId" OR s."marketplaceOrderId" = o."orderItemId" OR o.channel = 'TEMU'::product."StoreChannel" AND s."marketplaceOrderId" = concat('PO-', regexp_replace(o."amazonOrderId", '^PO-'::text, ''::text, 'i'::text)) OR o.channel = 'TEMU'::product."StoreChannel" AND o."orderItemId" IS NOT NULL AND s."marketplaceOrderId" = concat('PO-', regexp_replace(o."orderItemId", '^PO-'::text, ''::text, 'i'::text)))
                  ORDER BY ((EXISTS ( SELECT 1
                           FROM inventory."ShipmentLine" sl
                             LEFT JOIN inventory."Sku" sku ON sku.id = sl."skuId"
                          WHERE sl."shipmentId" = s.id AND COALESCE(sl."skuCodeSnapshot", sku.code) = o.sku))) DESC, (COALESCE(s."shippedAt", s."orderedAt")) DESC NULLS LAST
                 LIMIT 1) inv_ship ON true
             CROSS JOIN LATERAL ( SELECT COALESCE(product.iso_country(inv_ship.recipient_country), product.iso_country(o."shipCountry"), NULLIF(btrim(o."shipCountry"), ''::text)::character varying) AS country) dest
             CROSS JOIN LATERAL product.order_line_amounts(o, dest.country::text) amt
          WHERE o."purchaseDate" IS NOT NULL) line
     LEFT JOIN product.mv_overview_sku_meta meta ON meta.sku = line.sku;

REFRESH MATERIALIZED VIEW product.mv_overview_sales_daily;
REFRESH MATERIALIZED VIEW product.mv_overview_sku_daily;
REFRESH MATERIALIZED VIEW product.mv_overview_country_daily;
REFRESH MATERIALIZED VIEW product.mv_overview_fulfillment_daily;
REFRESH MATERIALIZED VIEW product.mv_sales_analytics_refund_daily;
REFRESH MATERIALIZED VIEW product.mv_sales_analytics_daily;
