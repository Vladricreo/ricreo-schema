-- ============================================================================
-- Panoramica snella: le quattro matview overview non rileggono più
-- v_order_line_pnl, aggregano mv_sales_analytics_daily (già al dettaglio
-- giorno × canale × store × sales channel × SKU × logistica × paese).
--
-- Prima ogni matview overview ricalcolava v_order_line_pnl (88k righe) e
-- v_order_line_refund su due anni: 4 × 30–170 s ogni ora, con il DB
-- condiviso saturo (incidente 12/10/2026, connessioni esaurite e Supabase
-- Auth in 500/504). Ora:
--   - vendite: GROUP BY su mv_sales_analytics_daily (cron Vendite, ogni 30 min);
--   - resi: una sola matview mv_overview_refund_daily (~13 s) al dettaglio
--     giorno × canale × SKU × paese × logistica, letta dalle quattro;
--   - ordini distinti (mv_overview_sales_daily): da StoreOrderLine, stessa
--     regola is_sold di v_order_line_pnl (un ordine con più SKU conta uno).
-- Le colonne e i nomi restano identici: service e Finance non cambiano.
-- Verifica 12/10: stessi valori della definizione precedente (unità, netto,
-- profitto, ordini) sulle righe non toccate da import tra un refresh e l'altro.
--
-- Freschezza: la panoramica è aggiornata quanto mv_sales_analytics_daily
-- all'ultimo refresh overview (cron ogni 6 ore + bottone Aggiorna).
--
-- finance.v_schermo_vendite_giorno (repo Ricreo-Finance, schermo da parete)
-- dipende da mv_overview_sales_daily: va ricreata identica dopo il DROP.
-- ============================================================================

-- I DROP vogliono lock esclusivo: meglio fallire e riprovare che accodare
-- dietro un REFRESH in corso tutte le letture della panoramica.
SET lock_timeout = '10s';

-- Stato dell'ultimo refresh della panoramica (stessa forma di SalesAnalyticsRefresh).
CREATE TABLE IF NOT EXISTS "product"."OverviewRefresh" (
  "id"          INTEGER        NOT NULL DEFAULT 1,
  "refreshedAt" TIMESTAMPTZ(6) NOT NULL,
  "rowCount"    INTEGER        NOT NULL DEFAULT 0,
  "durationMs"  INTEGER        NOT NULL DEFAULT 0,
  "source"      TEXT           NOT NULL DEFAULT 'cron',

  CONSTRAINT "OverviewRefresh_pkey" PRIMARY KEY ("id")
);

DROP VIEW IF EXISTS finance.v_schermo_vendite_giorno;
DROP MATERIALIZED VIEW IF EXISTS product.mv_overview_sales_daily;
DROP MATERIALIZED VIEW IF EXISTS product.mv_overview_sku_daily;
DROP MATERIALIZED VIEW IF EXISTS product.mv_overview_fulfillment_daily;
DROP MATERIALIZED VIEW IF EXISTS product.mv_overview_country_daily;

-- Resi degli ultimi due anni al dettaglio più fine che serve alla panoramica.
-- country_code e fulfillment con le stesse normalizzazioni delle matview sotto.
CREATE MATERIALIZED VIEW product.mv_overview_refund_daily AS
SELECT
  r.refund_day AS day,
  r.channel,
  r.sku,
  COALESCE(NULLIF(btrim(r.country_code), ''), 'XX') AS country_code,
  CASE WHEN r.fulfillment = 'FBA' THEN 'FBA' ELSE 'FBM' END AS fulfillment,
  sum(r.refund_units) AS refund_units,
  sum(r.refund_amount_eur) AS refund_amount_eur,
  sum(r.refund_vat_eur) AS refund_vat_eur,
  sum(r.refund_referral_eur) AS refund_referral_eur,
  sum(r.recovered_cogs_eur) AS recovered_cogs_eur,
  sum(r.return_fee_eur) AS return_fee_eur
FROM product.v_order_line_refund r
WHERE r.refund_day >= (CURRENT_DATE - '730 days'::interval)
GROUP BY 1, 2, 3, 4, 5;

CREATE UNIQUE INDEX mv_overview_refund_daily_uidx
  ON product.mv_overview_refund_daily (day, channel, sku, country_code, fulfillment);

-- Vendite e profitto per giorno e canale.
CREATE MATERIALIZED VIEW product.mv_overview_sales_daily AS
WITH sold AS (
  SELECT
    d.day,
    d.channel,
    sum(d.units) AS units,
    sum(d.gross_eur) AS gross_eur,
    sum(d.vat_eur) AS vat_eur,
    sum(d.referral_eur) AS referral_eur,
    sum(d.digital_eur) AS digital_eur,
    sum(d.fba_fee_eur) AS fba_fee_eur,
    sum(d.chargeback_eur) AS chargeback_eur,
    sum(d.other_fee_eur) AS other_fee_eur,
    sum(d.refund_commission_eur) AS refund_commission_eur,
    sum(d.fbm_shipping_eur) AS fbm_shipping_eur,
    sum(d.cogs_eur) AS cogs_eur,
    -- unit_cost_eur dipende solo dallo SKU: per riga aggregata è noto o no per tutte.
    sum(d.units) FILTER (WHERE d.unit_cost_eur IS NOT NULL) AS cogs_known_units
  FROM product.mv_sales_analytics_daily d
  WHERE d.day >= (CURRENT_DATE - '730 days'::interval)
  GROUP BY d.day, d.channel
), orders AS (
  -- Ordini distinti: le righe di mv_sales_analytics_daily sono per SKU, un
  -- ordine con più SKU si conterebbe più volte. Stessa regola is_sold della vista.
  SELECT
    o."purchaseDate"::date AS day,
    o.channel::text AS channel,
    count(DISTINCT COALESCE(o."amazonOrderId", (o.sku || ':') || o."purchaseDate"::date::text)) AS orders
  FROM product."StoreOrderLine" o
  WHERE o."purchaseDate" IS NOT NULL
    AND o."purchaseDate"::date >= (CURRENT_DATE - '730 days'::interval)
    AND lower(btrim(COALESCE(o."itemStatus", ''))) NOT IN ('cancelled', 'canceled', 'refunded', 'unfulfillable')
    AND COALESCE(o.quantity, 0) > 0
    AND (
      COALESCE(o."itemPrice", 0)
      - COALESCE(o."itemPromotionDiscount", 0)
      + COALESCE(o."shippingPrice", 0)
      - COALESCE(o."shipPromotionDiscount", 0)
      + COALESCE(o."giftWrapPrice", 0)
    ) > 0
  GROUP BY 1, 2
), refunds AS (
  SELECT
    r.day,
    r.channel,
    sum(r.refund_units) AS refund_units,
    sum(r.refund_amount_eur) AS refund_amount_eur,
    sum(r.refund_vat_eur) AS refund_vat_eur,
    sum(r.refund_referral_eur) AS refund_referral_eur,
    sum(r.recovered_cogs_eur) AS recovered_cogs_eur,
    sum(r.return_fee_eur) AS return_fee_eur
  FROM product.mv_overview_refund_daily r
  GROUP BY r.day, r.channel
)
SELECT
  COALESCE(s.day, r.day) AS day,
  COALESCE(s.channel, r.channel) AS channel,
  COALESCE(o.orders, 0::bigint)::integer AS orders,
  COALESCE(s.units, 0::bigint)::integer AS units,
  round(COALESCE(s.gross_eur, 0::numeric), 4) AS gross_eur,
  round(COALESCE(s.vat_eur, 0::numeric), 4) AS vat_eur,
  round(COALESCE(s.gross_eur, 0::numeric) - COALESCE(s.vat_eur, 0::numeric), 4) AS net_revenue_eur,
  round(COALESCE(s.referral_eur, 0::numeric), 4) AS referral_eur,
  round(COALESCE(s.digital_eur, 0::numeric), 4) AS digital_eur,
  round(COALESCE(s.fba_fee_eur, 0::numeric), 4) AS fba_fee_eur,
  round(COALESCE(s.chargeback_eur, 0::numeric), 4) AS chargeback_eur,
  round(COALESCE(s.other_fee_eur, 0::numeric), 4) AS other_fee_eur,
  round(COALESCE(s.refund_commission_eur, 0::numeric), 4) AS refund_commission_eur,
  round(COALESCE(s.fbm_shipping_eur, 0::numeric), 4) AS fbm_shipping_eur,
  round(COALESCE(s.cogs_eur, 0::numeric), 4) AS cogs_eur,
  COALESCE(s.cogs_known_units, 0::bigint)::integer AS cogs_known_units,
  COALESCE(r.refund_units, 0::bigint)::integer AS refund_units,
  round(COALESCE(r.refund_amount_eur, 0::numeric), 4) AS refund_amount_eur,
  round(COALESCE(r.refund_vat_eur, 0::numeric), 4) AS refund_vat_eur,
  round(COALESCE(r.refund_referral_eur, 0::numeric), 4) AS refund_referral_eur,
  round(COALESCE(r.recovered_cogs_eur, 0::numeric), 4) AS recovered_cogs_eur,
  round(COALESCE(r.return_fee_eur, 0::numeric), 4) AS return_fee_eur,
  round(
    COALESCE(s.gross_eur, 0::numeric) - COALESCE(r.refund_amount_eur, 0::numeric)
    - (COALESCE(s.vat_eur, 0::numeric) - COALESCE(r.refund_vat_eur, 0::numeric))
    - (COALESCE(s.referral_eur, 0::numeric) - COALESCE(r.refund_referral_eur, 0::numeric))
    - COALESCE(s.fba_fee_eur, 0::numeric) - COALESCE(s.chargeback_eur, 0::numeric)
    - COALESCE(s.other_fee_eur, 0::numeric) - COALESCE(s.refund_commission_eur, 0::numeric)
    - COALESCE(s.fbm_shipping_eur, 0::numeric)
    - (COALESCE(s.cogs_eur, 0::numeric) - COALESCE(r.recovered_cogs_eur, 0::numeric))
    - COALESCE(r.return_fee_eur, 0::numeric),
    4
  ) AS profit_eur
FROM sold s
FULL JOIN refunds r ON r.day = s.day AND r.channel = s.channel
LEFT JOIN orders o ON o.day = s.day AND o.channel = s.channel;

CREATE UNIQUE INDEX mv_overview_sales_daily_day_channel_uidx
  ON product.mv_overview_sales_daily (day, channel);

-- Vendite e profitto per giorno, canale e SKU.
CREATE MATERIALIZED VIEW product.mv_overview_sku_daily AS
WITH sold AS (
  SELECT
    d.day,
    d.channel,
    d.sku,
    max(d.asin) AS asin,
    max(d.product_name) AS product_name,
    sum(d.units) AS units,
    sum(d.gross_eur) AS gross_eur,
    sum(d.vat_eur) AS vat_eur,
    sum(d.referral_eur) AS referral_eur,
    sum(d.fba_fee_eur) AS fba_fee_eur,
    sum(d.chargeback_eur) AS chargeback_eur,
    sum(d.other_fee_eur) AS other_fee_eur,
    sum(d.refund_commission_eur) AS refund_commission_eur,
    sum(d.fbm_shipping_eur) AS fbm_shipping_eur,
    sum(d.cogs_eur) AS cogs_eur
  FROM product.mv_sales_analytics_daily d
  WHERE d.day >= (CURRENT_DATE - '730 days'::interval)
  GROUP BY d.day, d.channel, d.sku
), refunds AS (
  SELECT
    r.day,
    r.channel,
    r.sku,
    sum(r.refund_units) AS refund_units,
    sum(r.refund_amount_eur) AS refund_amount_eur,
    sum(r.refund_vat_eur) AS refund_vat_eur,
    sum(r.refund_referral_eur) AS refund_referral_eur,
    sum(r.recovered_cogs_eur) AS recovered_cogs_eur,
    sum(r.return_fee_eur) AS return_fee_eur
  FROM product.mv_overview_refund_daily r
  GROUP BY r.day, r.channel, r.sku
)
SELECT
  COALESCE(s.day, r.day) AS day,
  COALESCE(s.channel, r.channel) AS channel,
  COALESCE(s.sku, r.sku) AS sku,
  s.asin,
  s.product_name,
  COALESCE(s.units, 0::bigint)::integer AS units,
  round(COALESCE(s.gross_eur, 0::numeric), 4) AS gross_eur,
  round(COALESCE(s.gross_eur, 0::numeric) - COALESCE(s.vat_eur, 0::numeric), 4) AS net_revenue_eur,
  COALESCE(r.refund_units, 0::bigint)::integer AS refund_units,
  round(
    COALESCE(s.gross_eur, 0::numeric) - COALESCE(r.refund_amount_eur, 0::numeric)
    - (COALESCE(s.vat_eur, 0::numeric) - COALESCE(r.refund_vat_eur, 0::numeric))
    - (COALESCE(s.referral_eur, 0::numeric) - COALESCE(r.refund_referral_eur, 0::numeric))
    - COALESCE(s.fba_fee_eur, 0::numeric) - COALESCE(s.chargeback_eur, 0::numeric)
    - COALESCE(s.other_fee_eur, 0::numeric) - COALESCE(s.refund_commission_eur, 0::numeric)
    - COALESCE(s.fbm_shipping_eur, 0::numeric)
    - (COALESCE(s.cogs_eur, 0::numeric) - COALESCE(r.recovered_cogs_eur, 0::numeric))
    - COALESCE(r.return_fee_eur, 0::numeric),
    4
  ) AS profit_eur
FROM sold s
FULL JOIN refunds r ON r.day = s.day AND r.channel = s.channel AND r.sku = s.sku;

CREATE UNIQUE INDEX mv_overview_sku_daily_day_channel_sku_uidx
  ON product.mv_overview_sku_daily (day, channel, sku);
CREATE INDEX mv_overview_sku_daily_sku_idx
  ON product.mv_overview_sku_daily (sku);

-- Netto e profitto per giorno e logistica (FBA / FBM).
CREATE MATERIALIZED VIEW product.mv_overview_fulfillment_daily AS
WITH sold AS (
  SELECT
    d.day,
    d.fulfillment,
    sum(d.units) AS units,
    sum(d.gross_eur) AS gross_eur,
    sum(d.vat_eur) AS vat_eur,
    sum(d.referral_eur) AS referral_eur,
    sum(d.fba_fee_eur) AS fba_fee_eur,
    sum(d.chargeback_eur) AS chargeback_eur,
    sum(d.other_fee_eur) AS other_fee_eur,
    sum(d.refund_commission_eur) AS refund_commission_eur,
    sum(d.fbm_shipping_eur) AS fbm_shipping_eur,
    sum(d.cogs_eur) AS cogs_eur
  FROM product.mv_sales_analytics_daily d
  WHERE d.day >= (CURRENT_DATE - '730 days'::interval)
  GROUP BY d.day, d.fulfillment
), refunds AS (
  SELECT
    r.day,
    r.fulfillment,
    sum(r.refund_amount_eur) AS refund_amount_eur,
    sum(r.refund_vat_eur) AS refund_vat_eur,
    sum(r.refund_referral_eur) AS refund_referral_eur,
    sum(r.recovered_cogs_eur) AS recovered_cogs_eur,
    sum(r.return_fee_eur) AS return_fee_eur
  FROM product.mv_overview_refund_daily r
  GROUP BY r.day, r.fulfillment
)
SELECT
  COALESCE(s.day, r.day) AS day,
  COALESCE(s.fulfillment, r.fulfillment) AS fulfillment,
  COALESCE(s.units, 0::bigint)::integer AS units,
  round(COALESCE(s.gross_eur, 0::numeric) - COALESCE(s.vat_eur, 0::numeric), 4) AS net_revenue_eur,
  round(
    COALESCE(s.gross_eur, 0::numeric) - COALESCE(r.refund_amount_eur, 0::numeric)
    - (COALESCE(s.vat_eur, 0::numeric) - COALESCE(r.refund_vat_eur, 0::numeric))
    - (COALESCE(s.referral_eur, 0::numeric) - COALESCE(r.refund_referral_eur, 0::numeric))
    - COALESCE(s.fba_fee_eur, 0::numeric) - COALESCE(s.chargeback_eur, 0::numeric)
    - COALESCE(s.other_fee_eur, 0::numeric) - COALESCE(s.refund_commission_eur, 0::numeric)
    - COALESCE(s.fbm_shipping_eur, 0::numeric)
    - (COALESCE(s.cogs_eur, 0::numeric) - COALESCE(r.recovered_cogs_eur, 0::numeric))
    - COALESCE(r.return_fee_eur, 0::numeric),
    4
  ) AS profit_eur
FROM sold s
FULL JOIN refunds r ON r.day = s.day AND r.fulfillment = s.fulfillment;

CREATE UNIQUE INDEX mv_overview_fulfillment_daily_day_fulfillment_uidx
  ON product.mv_overview_fulfillment_daily (day, fulfillment);

-- Netto e profitto per giorno e paese di destinazione (XX = sconosciuto).
CREATE MATERIALIZED VIEW product.mv_overview_country_daily AS
WITH sold AS (
  SELECT
    d.day,
    -- mv_sales_analytics_daily tiene '' per il paese vuoto (già btrim): qui è XX.
    COALESCE(NULLIF(d.ship_country, ''), 'XX') AS country_code,
    sum(d.units) AS units,
    sum(d.gross_eur) AS gross_eur,
    sum(d.vat_eur) AS vat_eur,
    sum(d.referral_eur) AS referral_eur,
    sum(d.fba_fee_eur) AS fba_fee_eur,
    sum(d.chargeback_eur) AS chargeback_eur,
    sum(d.other_fee_eur) AS other_fee_eur,
    sum(d.refund_commission_eur) AS refund_commission_eur,
    sum(d.fbm_shipping_eur) AS fbm_shipping_eur,
    sum(d.cogs_eur) AS cogs_eur
  FROM product.mv_sales_analytics_daily d
  WHERE d.day >= (CURRENT_DATE - '730 days'::interval)
  GROUP BY 1, 2
), refunds AS (
  SELECT
    r.day,
    r.country_code,
    sum(r.refund_amount_eur) AS refund_amount_eur,
    sum(r.refund_vat_eur) AS refund_vat_eur,
    sum(r.refund_referral_eur) AS refund_referral_eur,
    sum(r.recovered_cogs_eur) AS recovered_cogs_eur,
    sum(r.return_fee_eur) AS return_fee_eur
  FROM product.mv_overview_refund_daily r
  GROUP BY r.day, r.country_code
)
SELECT
  COALESCE(s.day, r.day) AS day,
  COALESCE(s.country_code, r.country_code) AS country_code,
  COALESCE(s.units, 0::bigint)::integer AS units,
  round(COALESCE(s.gross_eur, 0::numeric) - COALESCE(s.vat_eur, 0::numeric), 4) AS net_revenue_eur,
  round(
    COALESCE(s.gross_eur, 0::numeric) - COALESCE(r.refund_amount_eur, 0::numeric)
    - (COALESCE(s.vat_eur, 0::numeric) - COALESCE(r.refund_vat_eur, 0::numeric))
    - (COALESCE(s.referral_eur, 0::numeric) - COALESCE(r.refund_referral_eur, 0::numeric))
    - COALESCE(s.fba_fee_eur, 0::numeric) - COALESCE(s.chargeback_eur, 0::numeric)
    - COALESCE(s.other_fee_eur, 0::numeric) - COALESCE(s.refund_commission_eur, 0::numeric)
    - COALESCE(s.fbm_shipping_eur, 0::numeric)
    - (COALESCE(s.cogs_eur, 0::numeric) - COALESCE(r.recovered_cogs_eur, 0::numeric))
    - COALESCE(r.return_fee_eur, 0::numeric),
    4
  ) AS profit_eur
FROM sold s
FULL JOIN refunds r ON r.day = s.day AND r.country_code = s.country_code;

CREATE UNIQUE INDEX mv_overview_country_daily_day_country_uidx
  ON product.mv_overview_country_daily (day, country_code);

-- Schermo da parete Ricreo-Finance: identica a supabase/migrations/20261103090000.
CREATE VIEW finance.v_schermo_vendite_giorno AS
SELECT
  d.day AS giorno,
  lower(d.channel) AS canale,
  d.orders AS ordini,
  d.gross_eur AS lordo
FROM product.mv_overview_sales_daily d;

ALTER VIEW finance.v_schermo_vendite_giorno OWNER TO postgres;
REVOKE ALL ON finance.v_schermo_vendite_giorno FROM public, anon, authenticated;
GRANT SELECT ON finance.v_schermo_vendite_giorno TO service_role;
