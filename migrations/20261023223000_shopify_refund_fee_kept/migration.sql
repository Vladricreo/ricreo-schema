-- ============================================================================
-- Resi Shopify: la commissione di pagamento non viene restituita.
--
-- Shopify Payments (come Etsy) trattiene la fee anche sugli ordini rimborsati:
-- la quota commissione del reso è 0. Unica modifica: `IN ('ETSY','SHOPIFY')`
-- al posto di `= 'ETSY'`. Colonne invariate; nessun refresh necessario perché
-- non esistono ancora righe Shopify.
-- ============================================================================

SET lock_timeout = '10s';

CREATE OR REPLACE VIEW product.v_order_line_refund AS
 WITH returns AS (
         SELECT DISTINCT ON (r_1.channel, (COALESCE(r_1."amazonOrderId", r_1.id)), r_1.sku) r_1.id,
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
            r_1."reasonDescription",
            r_1."refundAmount"
           FROM product."StoreReturnLine" r_1
          WHERE r_1.status IS DISTINCT FROM 'FINANCES'::text AND (upper(COALESCE(r_1.reason, ''::text)) <> ALL (ARRAY['DAMAGED_BY_FC'::text, 'DAMAGED_BY_CARRIER'::text])) OR r_1.status = 'FINANCES'::text AND (EXISTS ( SELECT 1
                   FROM product."StoreOrderLine" sold
                  WHERE sold.channel = r_1.channel AND sold."amazonOrderId" = r_1."amazonOrderId" AND sold.sku = r_1.sku AND COALESCE(sold.quantity, 0) > 0 AND (lower(btrim(COALESCE(sold."itemStatus", ''::text))) <> ALL (ARRAY['cancelled'::text, 'canceled'::text, 'refunded'::text, 'unfulfillable'::text]))))
          ORDER BY r_1.channel, (COALESCE(r_1."amazonOrderId", r_1.id)), r_1.sku, (
                CASE
                    WHEN r_1.status = 'FINANCES'::text THEN 1
                    ELSE 0
                END)
        )
 SELECT r."returnDate" AS refund_day,
    r.channel::text AS channel,
    r.sku,
    r.quantity AS refund_units,
        CASE
            WHEN tshare.f IS NOT NULL THEN round(o.gross_eur * tshare.f, 4)
            WHEN o.quantity > 0 THEN round(o.gross_eur * r.quantity::numeric / o.quantity::numeric, 4)
            ELSE 0::numeric
        END AS refund_amount_eur,
        CASE
            WHEN tshare.f IS NOT NULL THEN round(o.vat_eur * tshare.f, 4)
            WHEN o.quantity > 0 THEN round(o.vat_eur * r.quantity::numeric / o.quantity::numeric, 4)
            ELSE 0::numeric
        END AS refund_vat_eur,
        CASE
            WHEN r.channel = ANY (ARRAY['ETSY'::product."StoreChannel", 'SHOPIFY'::product."StoreChannel"]) THEN 0::numeric
            WHEN tshare.f IS NOT NULL THEN round(COALESCE(o.referral_eur, 0::numeric) * tshare.f, 4)
            WHEN o.quantity > 0 THEN round(COALESCE(o.referral_eur, 0::numeric) * r.quantity::numeric / o.quantity::numeric, 4)
            ELSE 0::numeric
        END AS refund_referral_eur,
    0::numeric AS recovered_cogs_eur,
        CASE
            WHEN r.channel = 'AMAZON'::product."StoreChannel" AND r.status IS DISTINCT FROM 'FINANCES'::text AND (o.fulfillment = 'FBA'::text OR upper(btrim(COALESCE(r."amazonFulfillment", ''::text))) = 'FBA'::text) THEN round(r.quantity::numeric * COALESCE(NULLIF(est."fbaFeeDomestic", 0::numeric), 3.5), 4)
            ELSE 0::numeric
        END AS return_fee_eur,
    r."storeKey" AS store_key,
        CASE
            WHEN restock.is_sellable THEN r.quantity
            ELSE 0
        END AS sellable_units,
    COALESCE(NULLIF(btrim(o.ship_country::text), ''::text), 'XX'::text) AS country_code,
    COALESCE(o.fulfillment, 'FBM'::text) AS fulfillment
   FROM returns r
     LEFT JOIN LATERAL ( SELECT p.quantity,
            p.gross_eur,
            p.vat_eur,
            p.referral_eur,
            p.digital_eur,
            p.unit_cost_eur,
            p.fulfillment,
            p.ship_country,
            p.purchase_day
           FROM product.v_order_line_pnl p
          WHERE p.channel = r.channel::text AND p.sku = r.sku AND (r."amazonOrderId" IS NOT NULL AND btrim(r."amazonOrderId") <> ''::text AND p.amazon_order_id = r."amazonOrderId" OR r."amazonOrderId" IS NULL OR btrim(r."amazonOrderId") = ''::text)
          ORDER BY (
                CASE
                    WHEN r."amazonOrderId" IS NOT NULL AND p.amazon_order_id = r."amazonOrderId" THEN 0
                    ELSE 1
                END), (
                CASE
                    WHEN p.is_sold THEN 0
                    ELSE 1
                END), p.purchase_day DESC NULLS LAST
         LIMIT 1) o ON true
     -- Temu con importo: quota = rimborso / lordo riga in valuta locale (max 100%).
     LEFT JOIN LATERAL ( SELECT LEAST(1::numeric, r."refundAmount" * product.eur_factor(sol.currency, o.purchase_day) / NULLIF(o.gross_eur, 0::numeric)) AS f
           FROM ( SELECT s.currency
                   FROM product."StoreOrderLine" s
                  WHERE s.channel = r.channel AND s."amazonOrderId" = r."amazonOrderId" AND s.sku = r.sku
                 LIMIT 1) sol
          WHERE r.channel = 'TEMU'::product."StoreChannel" AND r."refundAmount" IS NOT NULL AND r."refundAmount" > 0::numeric AND o.gross_eur > 0::numeric) tshare ON true
     LEFT JOIN LATERAL ( SELECT (upper(COALESCE(r.reason, ''::text)) <> ALL (ARRAY['DEFECTIVE'::text, 'QUALITY_UNACCEPTABLE'::text, 'DAMAGED_BY_FC'::text, 'DAMAGED_BY_CARRIER'::text])) AND (r.channel = 'AMAZON'::product."StoreChannel" AND (o.fulfillment = 'FBA'::text OR upper(btrim(COALESCE(r."amazonFulfillment", ''::text))) = 'FBA'::text) OR r.status IS DISTINCT FROM 'FINANCES'::text AND (r.status ~~* '%inventory%'::text OR r.status ~~* '%repackaged%'::text OR r.status ~~* '%sellable%'::text)) AS is_sellable) restock ON true
     LEFT JOIN LATERAL ( SELECT f."fbaFeeDomestic"
           FROM product."StoreSkuFeeEstimate" f
          WHERE f.channel = 'AMAZON'::product."StoreChannel" AND f.sku = r.sku
          ORDER BY (
                CASE
                    WHEN f."storeKey" = r."storeKey" THEN 0
                    ELSE 1
                END), f."updatedAt" DESC
         LIMIT 1) est ON true;
