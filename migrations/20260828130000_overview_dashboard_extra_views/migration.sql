-- ============================================================================
-- Panoramica: FBA vs FBM e ricavo per paese (matview, finestra 730 giorni).
-- Dipendono da product.v_order_line_pnl (migration overview_dashboard_views).
-- ============================================================================

DROP MATERIALIZED VIEW IF EXISTS "product"."mv_overview_fulfillment_daily";
DROP MATERIALIZED VIEW IF EXISTS "product"."mv_overview_country_daily";

-- Ricavo/profitto/unità per giorno e canale logistico (FBA oppure FBM).
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
      - p.digital_eur
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

-- Ricavo/profitto/unità per giorno e paese di destinazione (ISO-2, XX se assente).
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
      - p.digital_eur
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
