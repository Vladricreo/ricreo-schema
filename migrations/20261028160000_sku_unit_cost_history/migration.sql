-- ============================================================================
-- Storico costo unitario per SKU (28/10/2026).
--
-- Prima: v_order_line_pnl e mv_sales_analytics_daily prendevano il costo da
-- mv_overview_sku_meta al momento della lettura, quindi un costo cambiato
-- (materiali, manodopera recente, energia, Product.cost) riscriveva il COGS
-- di tutto lo storico in Ordini, Vendite, Panoramica e Finance.
--
-- Ora:
--   - product."SkuUnitCostHistory": periodi [validFrom, validTo) del costo per
--     SKU (validTo NULL = in vigore). Una riga nuova solo quando il costo cambia;
--   - product.snapshot_sku_unit_cost(): confronta mv_overview_sku_meta con il
--     periodo aperto e chiude/apre i periodi. La chiama refreshMatviews() subito
--     dopo il refresh di mv_overview_sku_meta;
--   - le due viste usano il costo in vigore nel giorno dell'ordine, con
--     fallback sul costo attuale per gli SKU non ancora registrati.
--
-- Lo storico prima di oggi non esiste: il primo periodo di ogni SKU parte dal
-- 1900-01-01 col costo attuale, quindi oggi i numeri non cambiano. Da domani
-- un cambio di costo vale solo dal giorno in cui viene registrato.
--
-- Le viste mantengono colonne e tipi: matview overview, v_order_line_refund e
-- Finance non vanno ricreate.
-- ============================================================================

SET lock_timeout = '10s';

CREATE TABLE "product"."SkuUnitCostHistory" (
    "sku" TEXT NOT NULL,
    "validFrom" DATE NOT NULL,
    "validTo" DATE,
    "unitCostEur" NUMERIC NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SkuUnitCostHistory_pkey" PRIMARY KEY ("sku", "validFrom"),
    CONSTRAINT "SkuUnitCostHistory_period_check" CHECK ("validTo" IS NULL OR "validTo" > "validFrom")
);

-- Un solo periodo aperto per SKU.
CREATE UNIQUE INDEX "SkuUnitCostHistory_open_key"
    ON "product"."SkuUnitCostHistory" ("sku")
    WHERE "validTo" IS NULL;

-- Registra i costi cambiati rispetto al periodo aperto. Ritorna gli SKU toccati.
-- Sotto il mezzo centesimo non è un cambio di costo (manodopera e energia
-- oscillano di decimi di centesimo a ogni refresh).
CREATE OR REPLACE FUNCTION product.snapshot_sku_unit_cost(p_day DATE DEFAULT CURRENT_DATE)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_touched INTEGER := 0;
  v_rows INTEGER;
BEGIN
  CREATE TEMP TABLE IF NOT EXISTS _sku_cost_now (sku TEXT PRIMARY KEY, cost NUMERIC) ON COMMIT DROP;
  TRUNCATE _sku_cost_now;

  INSERT INTO _sku_cost_now (sku, cost)
  SELECT m.sku, round(m.unit_cost_eur, 4)
  FROM product.mv_overview_sku_meta m
  WHERE m.sku IS NOT NULL AND m.unit_cost_eur > 0;

  -- Cambio nello stesso giorno: si corregge il periodo appena aperto.
  UPDATE product."SkuUnitCostHistory" h
  SET "unitCostEur" = n.cost, "updatedAt" = CURRENT_TIMESTAMP
  FROM _sku_cost_now n
  WHERE h.sku = n.sku
    AND h."validTo" IS NULL
    AND h."validFrom" = p_day
    AND abs(h."unitCostEur" - n.cost) >= 0.005;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  v_touched := v_touched + v_rows;

  -- Cambio rispetto a un periodo dei giorni prima: lo chiude a p_day e ne apre uno.
  WITH closed AS (
    UPDATE product."SkuUnitCostHistory" h
    SET "validTo" = p_day, "updatedAt" = CURRENT_TIMESTAMP
    FROM _sku_cost_now n
    WHERE h.sku = n.sku
      AND h."validTo" IS NULL
      AND h."validFrom" < p_day
      AND abs(h."unitCostEur" - n.cost) >= 0.005
    RETURNING h.sku
  )
  INSERT INTO product."SkuUnitCostHistory" (sku, "validFrom", "validTo", "unitCostEur")
  SELECT n.sku, p_day, NULL, n.cost
  FROM closed c
  JOIN _sku_cost_now n ON n.sku = c.sku;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  v_touched := v_touched + v_rows;

  -- SKU mai visti: nessun costo precedente noto, il primo periodo copre lo storico.
  INSERT INTO product."SkuUnitCostHistory" (sku, "validFrom", "validTo", "unitCostEur")
  SELECT n.sku, DATE '1900-01-01', NULL, n.cost
  FROM _sku_cost_now n
  WHERE NOT EXISTS (
    SELECT 1 FROM product."SkuUnitCostHistory" h WHERE h.sku = n.sku
  );
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  v_touched := v_touched + v_rows;

  RETURN v_touched;
END;
$$;

-- Primo periodo per tutti gli SKU con il costo attuale.
SELECT product.snapshot_sku_unit_cost();

-- Costo in vigore nel giorno dell'ordine, altrimenti quello attuale.
CREATE OR REPLACE VIEW product.mv_sales_analytics_daily AS
SELECT
  d.day,
  d.channel,
  d.store_key,
  d.sales_channel,
  d.sku,
  d.fulfillment,
  d.ship_country,
  COALESCE(meta.asin, d.asin) AS asin,
  COALESCE(meta.product_name, d.product_name) AS product_name,
  meta.image_url,
  COALESCE(hc."unitCostEur", meta.unit_cost_eur) AS unit_cost_eur,
  d.units,
  d.gross_eur,
  d.vat_eur,
  d.customer_shipping_eur,
  d.customer_shipping_tax_eur,
  d.referral_eur,
  d.digital_eur,
  d.fba_fee_eur,
  d.chargeback_eur,
  d.other_fee_eur,
  d.refund_commission_eur,
  d.fbm_shipping_eur,
  CASE
    WHEN COALESCE(hc."unitCostEur", meta.unit_cost_eur) IS NULL THEN 0::numeric
    ELSE round(COALESCE(hc."unitCostEur", meta.unit_cost_eur) * d.units::numeric, 4)
  END AS cogs_eur,
  d.has_fee_estimate,
  d.real_cost_units,
  d.provisional_cost_units
FROM product.sales_analytics_daily d
LEFT JOIN product.mv_overview_sku_meta meta ON meta.sku = d.sku
LEFT JOIN product."SkuUnitCostHistory" hc
  ON hc.sku = d.sku
  AND d.day >= hc."validFrom"
  AND (hc."validTo" IS NULL OR d.day < hc."validTo");

-- Stessa vista di produzione: cambiano solo unit_cost_eur, cogs_eur e il JOIN sullo storico.
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
    COALESCE(hc."unitCostEur", meta.unit_cost_eur) AS unit_cost_eur,
        CASE
            WHEN line.is_sold AND COALESCE(hc."unitCostEur", meta.unit_cost_eur) IS NOT NULL THEN round(COALESCE(hc."unitCostEur", meta.unit_cost_eur) * GREATEST(line.quantity, 0)::numeric, 4)
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
            fx.eur_factor,
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
             CROSS JOIN LATERAL product.order_line_amounts_rows(o.*, dest.country::text) amt(gross_local, shipping_local, item_vat_local, shipping_vat_local, vat_local, vat_mode)
             CROSS JOIN LATERAL product.eur_factor(o.currency, o."purchaseDate"::date) fx(eur_factor)
          WHERE o."purchaseDate" IS NOT NULL) line
     LEFT JOIN product.mv_overview_sku_meta meta ON meta.sku = line.sku
     LEFT JOIN product."SkuUnitCostHistory" hc ON hc.sku = line.sku AND line.purchase_day >= hc."validFrom" AND (hc."validTo" IS NULL OR line.purchase_day < hc."validTo");
