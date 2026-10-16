-- ============================================================================
-- v_order_line_pnl: tasso di cambio calcolato una volta per riga, non dieci.
--
-- Incidente 16/10/2026 11:30 (ora italiana): DB condiviso in swap, query banali
-- a 10–30 s. Il REFRESH di mv_sales_analytics_daily durava 34 s, ~80 volte al
-- giorno.
--
-- Causa: line.eur_factor era product.eur_factor(...) nella SELECT della
-- subquery `line`. Postgres appiattisce la subquery e ricopia l'espressione in
-- ogni colonna che la usa: 10 importi in euro = 10 chiamate per riga. La
-- funzione ha sottoquery, quindi non viene inlineata: ~25 µs a chiamata,
-- 84k righe × 10 = ~20 s dei 34 s del refresh (EXPLAIN ANALYZE 16/10).
--
-- Fix: eur_factor passa in FROM come CROSS JOIN LATERAL (Function Scan, una
-- chiamata per riga). Nessun'altra modifica: colonne, ordine e valori uguali.
-- ============================================================================

-- La vista è letta dai REFRESH delle matview: se uno è in corso meglio
-- fallire subito e riprovare che accodare dietro il lock tutto il resto.
SET lock_timeout = '10s';

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
             CROSS JOIN LATERAL product.order_line_amounts_rows(o, dest.country::text) amt
             CROSS JOIN LATERAL product.eur_factor(o.currency, o."purchaseDate"::date) fx(eur_factor)
          WHERE o."purchaseDate" IS NOT NULL) line
     LEFT JOIN product.mv_overview_sku_meta meta ON meta.sku = line.sku;
