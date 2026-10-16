-- ============================================================================
-- mv_sales_analytics_daily: da matview a tabella aggiornata per giorni.
--
-- Incidente 16/10/2026: DB condiviso in swap. Il REFRESH CONCURRENTLY di
-- mv_sales_analytics_daily rifaceva tutto lo storico (84k righe ordine) ~80
-- volte al giorno: 34 s e ~125 MB di file temporanei a giro (il confronto
-- riga per riga del CONCURRENTLY con work_mem 5 MB). 20261016100000 ha già
-- portato il calcolo a ~12 s; qui si smette di rifarlo tutto.
--
-- Ora:
--   - product.sales_analytics_daily: stesse somme e stessa grana della
--     matview (giorno × canale × store × sales channel × SKU × logistica ×
--     paese), senza anagrafica e COGS;
--   - product.sync_sales_analytics_daily(): ricalcola solo i giorni con righe
--     ordine, fee, ordini Amazon, spedizioni o cambi modificati dall'ultimo
--     giro (DELETE + INSERT nella stessa transazione: chi legge vede i dati
--     vecchi fino al commit, nessun lock). Di notte (3–5 ora italiana) e se
--     l'ultima ricostruzione ha più di 36 ore rifà tutto: copre righe
--     cancellate e cambi a monte senza updatedAt;
--   - product.mv_sales_analytics_daily diventa una vista: stesse colonne, con
--     anagrafica, immagine, costo unitario e COGS presi al momento da
--     mv_overview_sku_meta (un costo cambiato vale subito su tutto lo storico).
--     Service, matview overview e Finance non cambiano.
--
-- Il nome mv_ resta per non toccare chi la legge, anche se non è più una matview.
--
-- Una migration che cambia i conti di v_order_line_pnl (regole IVA, fee, ...)
-- deve chiudere con: SELECT * FROM product.sync_sales_analytics_daily(true);
--
-- Le quattro matview overview e finance.v_schermo_vendite_giorno dipendono da
-- mv_sales_analytics_daily: vanno ricreate identiche (definizioni copiate da
-- produzione il 16/10/2026).
-- ============================================================================

-- I DROP vogliono lock esclusivo: meglio fallire e riprovare che accodare
-- dietro un REFRESH in corso tutte le letture della panoramica.
SET lock_timeout = '10s';

-- Somme vendite per giorno. La scrive solo sync_sales_analytics_daily().
-- asin e product_name: valore della riga ordine (con l'anagrafica del momento
-- del calcolo), la vista preferisce mv_overview_sku_meta.
CREATE TABLE product.sales_analytics_daily (
  day                       DATE           NOT NULL,
  channel                   TEXT           NOT NULL,
  store_key                 TEXT           NOT NULL,
  sales_channel             TEXT           NOT NULL,
  sku                       TEXT           NOT NULL,
  fulfillment               TEXT           NOT NULL,
  ship_country              TEXT           NOT NULL,
  asin                      TEXT,
  product_name              TEXT,
  units                     INTEGER        NOT NULL,
  gross_eur                 DECIMAL(16, 4) NOT NULL,
  vat_eur                   DECIMAL(16, 4) NOT NULL,
  customer_shipping_eur     DECIMAL(16, 4) NOT NULL,
  customer_shipping_tax_eur DECIMAL(16, 4) NOT NULL,
  referral_eur              DECIMAL(16, 4) NOT NULL,
  digital_eur               DECIMAL(16, 4) NOT NULL,
  fba_fee_eur               DECIMAL(16, 4) NOT NULL,
  chargeback_eur            DECIMAL(16, 4) NOT NULL,
  other_fee_eur             DECIMAL(16, 4) NOT NULL,
  refund_commission_eur     DECIMAL(16, 4) NOT NULL,
  fbm_shipping_eur          DECIMAL(16, 4) NOT NULL,
  has_fee_estimate          BOOLEAN        NOT NULL,
  real_cost_units           INTEGER        NOT NULL,
  provisional_cost_units    INTEGER        NOT NULL,

  CONSTRAINT sales_analytics_daily_pkey
    PRIMARY KEY (day, channel, store_key, sales_channel, sku, fulfillment, ship_country)
);

CREATE INDEX sales_analytics_daily_sku_day_idx
  ON product.sales_analytics_daily (sku, day);

-- Singleton: inizio dell'ultimo giro riuscito e dell'ultima ricostruzione completa.
CREATE TABLE product.sales_analytics_daily_sync (
  id        INTEGER        NOT NULL DEFAULT 1,
  synced_at TIMESTAMPTZ(6),
  full_at   TIMESTAMPTZ(6),

  CONSTRAINT sales_analytics_daily_sync_pkey PRIMARY KEY (id)
);

INSERT INTO product.sales_analytics_daily_sync (id) VALUES (1);

-- Aggiorna sales_analytics_daily. p_full = true rifà tutto lo storico.
-- Ritorna: 'days' o 'full', giorni ricalcolati (null se full), righe scritte.
CREATE FUNCTION product.sync_sales_analytics_daily(p_full BOOLEAN DEFAULT false)
RETURNS TABLE (sync_mode TEXT, synced_days INTEGER, written_rows INTEGER)
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_started TIMESTAMPTZ := now();
  v_since TIMESTAMPTZ;
  v_full_at TIMESTAMPTZ;
  v_full BOOLEAN;
  v_days DATE[];
  v_rows INTEGER := 0;
BEGIN
  -- Un giro alla volta: il secondo aspetta qui che il primo finisca.
  SELECT s.synced_at, s.full_at INTO v_since, v_full_at
  FROM product.sales_analytics_daily_sync s
  WHERE s.id = 1
  FOR UPDATE;

  v_full := p_full
    OR v_since IS NULL
    OR v_full_at IS NULL
    OR v_full_at < v_started - interval '36 hours'
    OR (
      v_full_at < v_started - interval '20 hours'
      AND extract(hour FROM v_started AT TIME ZONE 'Europe/Rome') BETWEEN 3 AND 4
    );

  IF NOT v_full THEN
    -- Margine: una transazione lunga può committare dopo l'ultimo giro righe
    -- con updatedAt di prima.
    v_since := v_since - interval '30 minutes';

    -- Giorni d'acquisto delle righe ordine toccate, direttamente o da ciò che
    -- v_order_line_pnl ci aggancia: fee, ordine/righe Amazon (IVA), spedizione
    -- (costo e paese), cambio del giorno.
    WITH changed_orders AS (
      SELECT f.channel, f."amazonOrderId" AS order_id
      FROM product."StoreOrderFee" f
      WHERE f."updatedAt" >= v_since
      UNION
      SELECT 'AMAZON'::product."StoreChannel", ao."amazonOrderId"
      FROM inventory."AmazonOrder" ao
      WHERE ao."updatedAt" >= v_since
      UNION
      SELECT 'AMAZON'::product."StoreChannel", ao."amazonOrderId"
      FROM inventory."AmazonOrderItem" ai
      JOIN inventory."AmazonOrder" ao ON ao.id = ai."orderId"
      WHERE ai."updatedAt" >= v_since
    ),
    changed_shipments AS (
      SELECT s."marketplaceOrderId" AS ref
      FROM inventory."Shipment" s
      WHERE s."updatedAt" >= v_since
      UNION
      SELECT s."marketplaceOrderId"
      FROM inventory."ShipmentLine" l
      JOIN inventory."Shipment" s ON s.id = l."shipmentId"
      WHERE l."updatedAt" >= v_since
    ),
    -- Temu: la spedizione ha PO-xxx, la riga ordine può avere xxx.
    changed_refs AS (
      SELECT cs.ref FROM changed_shipments cs WHERE cs.ref IS NOT NULL
      UNION
      SELECT regexp_replace(cs.ref, '^PO-', '', 'i') FROM changed_shipments cs WHERE cs.ref IS NOT NULL
    ),
    -- Un cambio nuovo vale dal suo giorno in poi (eur_factor prende l'ultimo <= giorno).
    changed_fx AS (
      SELECT r.currency, min(r."rateDate") AS from_day
      FROM product."ExchangeRateDaily" r
      WHERE r."updatedAt" >= v_since
        AND r.base = 'EUR'
      GROUP BY r.currency
    )
    SELECT array_agg(DISTINCT t.day) INTO v_days
    FROM (
      SELECT o."purchaseDate"::date AS day
      FROM product."StoreOrderLine" o
      WHERE o."updatedAt" >= v_since
      UNION ALL
      SELECT o."purchaseDate"::date
      FROM changed_orders c
      JOIN product."StoreOrderLine" o ON o.channel = c.channel AND o."amazonOrderId" = c.order_id
      UNION ALL
      SELECT o."purchaseDate"::date
      FROM changed_refs c
      JOIN product."StoreOrderLine" o ON o."amazonOrderId" = c.ref
      UNION ALL
      SELECT o."purchaseDate"::date
      FROM changed_refs c
      JOIN product."StoreOrderLine" o ON o."orderItemId" = c.ref
      UNION ALL
      SELECT o."purchaseDate"::date
      FROM changed_fx c
      JOIN product."StoreOrderLine" o
        ON upper(btrim(o.currency)) = c.currency
       AND o."purchaseDate"::date >= c.from_day
    ) t
    WHERE t.day IS NOT NULL;
  END IF;

  IF v_full OR v_days IS NOT NULL THEN
    DELETE FROM product.sales_analytics_daily d
    WHERE v_full OR d.day = ANY (v_days);

    -- Stesso SELECT della vecchia matview, meno anagrafica e COGS.
    INSERT INTO product.sales_analytics_daily (
      day, channel, store_key, sales_channel, sku, fulfillment, ship_country,
      asin, product_name, units, gross_eur, vat_eur, customer_shipping_eur,
      customer_shipping_tax_eur, referral_eur, digital_eur, fba_fee_eur,
      chargeback_eur, other_fee_eur, refund_commission_eur, fbm_shipping_eur,
      has_fee_estimate, real_cost_units, provisional_cost_units
    )
    SELECT
      p.purchase_day,
      p.channel,
      p.store_key,
      COALESCE(p.sales_channel, ''),
      p.sku,
      CASE WHEN p.fulfillment = 'FBA' THEN 'FBA' ELSE 'FBM' END,
      COALESCE(NULLIF(btrim(p.ship_country::text), ''), ''),
      max(p.asin),
      max(p.product_name),
      sum(p.quantity)::integer,
      round(sum(p.gross_eur), 4),
      round(sum(p.vat_eur), 4),
      round(sum(p.customer_shipping_eur), 4),
      round(sum(p.customer_shipping_tax_eur), 4),
      round(sum(p.referral_eur), 4),
      round(sum(p.digital_eur), 4),
      round(sum(p.fba_fee_eur), 4),
      round(sum(p.chargeback_eur), 4),
      round(sum(p.other_fee_eur), 4),
      round(sum(p.refund_commission_eur), 4),
      round(sum(p.fbm_shipping_eur), 4),
      bool_or(p.has_fee_estimate),
      COALESCE(sum(p.quantity) FILTER (WHERE p.cost_source = 'real'), 0)::integer,
      COALESCE(sum(p.quantity) FILTER (WHERE p.cost_source = 'provisional'), 0)::integer
    FROM product.v_order_line_pnl p
    WHERE p.is_sold
      AND (v_full OR p.purchase_day = ANY (v_days))
    GROUP BY 1, 2, 3, 4, 5, 6, 7;

    GET DIAGNOSTICS v_rows = ROW_COUNT;
  END IF;

  UPDATE product.sales_analytics_daily_sync s
  SET synced_at = v_started,
      full_at = CASE WHEN v_full THEN v_started ELSE s.full_at END
  WHERE s.id = 1;

  RETURN QUERY SELECT
    CASE WHEN v_full THEN 'full' ELSE 'days' END,
    CASE WHEN v_full THEN NULL ELSE COALESCE(cardinality(v_days), 0) END,
    v_rows;
END;
$$;

REVOKE ALL ON FUNCTION product.sync_sales_analytics_daily(BOOLEAN) FROM PUBLIC;

-- Primo riempimento (tutto lo storico, ~12 s), prima dei DROP: così i lock
-- esclusivi durano solo il tempo di ricreare le viste.
SELECT * FROM product.sync_sales_analytics_daily(true);

DROP VIEW IF EXISTS finance.v_schermo_vendite_giorno;
DROP MATERIALIZED VIEW IF EXISTS product.mv_overview_sales_daily;
DROP MATERIALIZED VIEW IF EXISTS product.mv_overview_sku_daily;
DROP MATERIALIZED VIEW IF EXISTS product.mv_overview_fulfillment_daily;
DROP MATERIALIZED VIEW IF EXISTS product.mv_overview_country_daily;
DROP MATERIALIZED VIEW IF EXISTS product.mv_sales_analytics_daily;

-- Stesse colonne, nello stesso ordine, della vecchia matview.
-- unit_cost_eur ha al massimo 4 decimali: round(costo × unità, 4) è uguale
-- alla somma per riga ordine che faceva la matview.
CREATE VIEW product.mv_sales_analytics_daily AS
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
  meta.unit_cost_eur,
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
    WHEN meta.unit_cost_eur IS NULL THEN 0::numeric
    ELSE round(meta.unit_cost_eur * d.units::numeric, 4)
  END AS cogs_eur,
  d.has_fee_estimate,
  d.real_cost_units,
  d.provisional_cost_units
FROM product.sales_analytics_daily d
LEFT JOIN product.mv_overview_sku_meta meta ON meta.sku = d.sku;

-- Matview overview e vista Finance: definizioni di produzione, invariate.

CREATE MATERIALIZED VIEW product.mv_overview_sales_daily AS
 WITH sold AS (
         SELECT d.day,
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
            sum(d.units) FILTER (WHERE d.unit_cost_eur IS NOT NULL) AS cogs_known_units
           FROM product.mv_sales_analytics_daily d
          WHERE d.day >= (CURRENT_DATE - '730 days'::interval)
          GROUP BY d.day, d.channel
        ), orders AS (
         SELECT o_1."purchaseDate"::date AS day,
            o_1.channel::text AS channel,
            count(DISTINCT COALESCE(o_1."amazonOrderId", (o_1.sku || ':'::text) || o_1."purchaseDate"::date::text)) AS orders
           FROM product."StoreOrderLine" o_1
          WHERE o_1."purchaseDate" IS NOT NULL AND o_1."purchaseDate"::date >= (CURRENT_DATE - '730 days'::interval) AND (lower(btrim(COALESCE(o_1."itemStatus", ''::text))) <> ALL (ARRAY['cancelled'::text, 'canceled'::text, 'refunded'::text, 'unfulfillable'::text])) AND COALESCE(o_1.quantity, 0) > 0 AND (COALESCE(o_1."itemPrice", 0::numeric) - COALESCE(o_1."itemPromotionDiscount", 0::numeric) + COALESCE(o_1."shippingPrice", 0::numeric) - COALESCE(o_1."shipPromotionDiscount", 0::numeric) + COALESCE(o_1."giftWrapPrice", 0::numeric)) > 0::numeric
          GROUP BY (o_1."purchaseDate"::date), (o_1.channel::text)
        ), refunds AS (
         SELECT r_1.day,
            r_1.channel,
            sum(r_1.refund_units) AS refund_units,
            sum(r_1.refund_amount_eur) AS refund_amount_eur,
            sum(r_1.refund_vat_eur) AS refund_vat_eur,
            sum(r_1.refund_referral_eur) AS refund_referral_eur,
            sum(r_1.recovered_cogs_eur) AS recovered_cogs_eur,
            sum(r_1.return_fee_eur) AS return_fee_eur
           FROM product.mv_overview_refund_daily r_1
          GROUP BY r_1.day, r_1.channel
        )
 SELECT COALESCE(s.day, r.day) AS day,
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
    COALESCE(r.refund_units, 0::bigint::numeric)::integer AS refund_units,
    round(COALESCE(r.refund_amount_eur, 0::numeric), 4) AS refund_amount_eur,
    round(COALESCE(r.refund_vat_eur, 0::numeric), 4) AS refund_vat_eur,
    round(COALESCE(r.refund_referral_eur, 0::numeric), 4) AS refund_referral_eur,
    round(COALESCE(r.recovered_cogs_eur, 0::numeric), 4) AS recovered_cogs_eur,
    round(COALESCE(r.return_fee_eur, 0::numeric), 4) AS return_fee_eur,
    round(COALESCE(s.gross_eur, 0::numeric) - COALESCE(r.refund_amount_eur, 0::numeric) - (COALESCE(s.vat_eur, 0::numeric) - COALESCE(r.refund_vat_eur, 0::numeric)) - (COALESCE(s.referral_eur, 0::numeric) - COALESCE(r.refund_referral_eur, 0::numeric)) - COALESCE(s.fba_fee_eur, 0::numeric) - COALESCE(s.chargeback_eur, 0::numeric) - COALESCE(s.other_fee_eur, 0::numeric) - COALESCE(s.refund_commission_eur, 0::numeric) - COALESCE(s.fbm_shipping_eur, 0::numeric) - (COALESCE(s.cogs_eur, 0::numeric) - COALESCE(r.recovered_cogs_eur, 0::numeric)) - COALESCE(r.return_fee_eur, 0::numeric), 4) AS profit_eur
   FROM sold s
     FULL JOIN refunds r ON r.day = s.day AND r.channel = s.channel
     LEFT JOIN orders o ON o.day = s.day AND o.channel = s.channel;

CREATE UNIQUE INDEX mv_overview_sales_daily_day_channel_uidx ON product.mv_overview_sales_daily USING btree (day, channel);

CREATE MATERIALIZED VIEW product.mv_overview_sku_daily AS
 WITH sold AS (
         SELECT d.day,
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
         SELECT r_1.day,
            r_1.channel,
            r_1.sku,
            sum(r_1.refund_units) AS refund_units,
            sum(r_1.refund_amount_eur) AS refund_amount_eur,
            sum(r_1.refund_vat_eur) AS refund_vat_eur,
            sum(r_1.refund_referral_eur) AS refund_referral_eur,
            sum(r_1.recovered_cogs_eur) AS recovered_cogs_eur,
            sum(r_1.return_fee_eur) AS return_fee_eur
           FROM product.mv_overview_refund_daily r_1
          GROUP BY r_1.day, r_1.channel, r_1.sku
        )
 SELECT COALESCE(s.day, r.day) AS day,
    COALESCE(s.channel, r.channel) AS channel,
    COALESCE(s.sku, r.sku) AS sku,
    s.asin,
    s.product_name,
    COALESCE(s.units, 0::bigint)::integer AS units,
    round(COALESCE(s.gross_eur, 0::numeric), 4) AS gross_eur,
    round(COALESCE(s.gross_eur, 0::numeric) - COALESCE(s.vat_eur, 0::numeric), 4) AS net_revenue_eur,
    COALESCE(r.refund_units, 0::bigint::numeric)::integer AS refund_units,
    round(COALESCE(s.gross_eur, 0::numeric) - COALESCE(r.refund_amount_eur, 0::numeric) - (COALESCE(s.vat_eur, 0::numeric) - COALESCE(r.refund_vat_eur, 0::numeric)) - (COALESCE(s.referral_eur, 0::numeric) - COALESCE(r.refund_referral_eur, 0::numeric)) - COALESCE(s.fba_fee_eur, 0::numeric) - COALESCE(s.chargeback_eur, 0::numeric) - COALESCE(s.other_fee_eur, 0::numeric) - COALESCE(s.refund_commission_eur, 0::numeric) - COALESCE(s.fbm_shipping_eur, 0::numeric) - (COALESCE(s.cogs_eur, 0::numeric) - COALESCE(r.recovered_cogs_eur, 0::numeric)) - COALESCE(r.return_fee_eur, 0::numeric), 4) AS profit_eur
   FROM sold s
     FULL JOIN refunds r ON r.day = s.day AND r.channel = s.channel AND r.sku = s.sku;

CREATE UNIQUE INDEX mv_overview_sku_daily_day_channel_sku_uidx ON product.mv_overview_sku_daily USING btree (day, channel, sku);
CREATE INDEX mv_overview_sku_daily_sku_idx ON product.mv_overview_sku_daily USING btree (sku);

CREATE MATERIALIZED VIEW product.mv_overview_fulfillment_daily AS
 WITH sold AS (
         SELECT d.day,
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
         SELECT r_1.day,
            r_1.fulfillment,
            sum(r_1.refund_amount_eur) AS refund_amount_eur,
            sum(r_1.refund_vat_eur) AS refund_vat_eur,
            sum(r_1.refund_referral_eur) AS refund_referral_eur,
            sum(r_1.recovered_cogs_eur) AS recovered_cogs_eur,
            sum(r_1.return_fee_eur) AS return_fee_eur
           FROM product.mv_overview_refund_daily r_1
          GROUP BY r_1.day, r_1.fulfillment
        )
 SELECT COALESCE(s.day, r.day) AS day,
    COALESCE(s.fulfillment, r.fulfillment) AS fulfillment,
    COALESCE(s.units, 0::bigint)::integer AS units,
    round(COALESCE(s.gross_eur, 0::numeric) - COALESCE(s.vat_eur, 0::numeric), 4) AS net_revenue_eur,
    round(COALESCE(s.gross_eur, 0::numeric) - COALESCE(r.refund_amount_eur, 0::numeric) - (COALESCE(s.vat_eur, 0::numeric) - COALESCE(r.refund_vat_eur, 0::numeric)) - (COALESCE(s.referral_eur, 0::numeric) - COALESCE(r.refund_referral_eur, 0::numeric)) - COALESCE(s.fba_fee_eur, 0::numeric) - COALESCE(s.chargeback_eur, 0::numeric) - COALESCE(s.other_fee_eur, 0::numeric) - COALESCE(s.refund_commission_eur, 0::numeric) - COALESCE(s.fbm_shipping_eur, 0::numeric) - (COALESCE(s.cogs_eur, 0::numeric) - COALESCE(r.recovered_cogs_eur, 0::numeric)) - COALESCE(r.return_fee_eur, 0::numeric), 4) AS profit_eur
   FROM sold s
     FULL JOIN refunds r ON r.day = s.day AND r.fulfillment = s.fulfillment;

CREATE UNIQUE INDEX mv_overview_fulfillment_daily_day_fulfillment_uidx ON product.mv_overview_fulfillment_daily USING btree (day, fulfillment);

CREATE MATERIALIZED VIEW product.mv_overview_country_daily AS
 WITH sold AS (
         SELECT d.day,
            COALESCE(NULLIF(d.ship_country, ''::text), 'XX'::text) AS country_code,
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
          GROUP BY d.day, (COALESCE(NULLIF(d.ship_country, ''::text), 'XX'::text))
        ), refunds AS (
         SELECT r_1.day,
            r_1.country_code,
            sum(r_1.refund_amount_eur) AS refund_amount_eur,
            sum(r_1.refund_vat_eur) AS refund_vat_eur,
            sum(r_1.refund_referral_eur) AS refund_referral_eur,
            sum(r_1.recovered_cogs_eur) AS recovered_cogs_eur,
            sum(r_1.return_fee_eur) AS return_fee_eur
           FROM product.mv_overview_refund_daily r_1
          GROUP BY r_1.day, r_1.country_code
        )
 SELECT COALESCE(s.day, r.day) AS day,
    COALESCE(s.country_code, r.country_code) AS country_code,
    COALESCE(s.units, 0::bigint)::integer AS units,
    round(COALESCE(s.gross_eur, 0::numeric) - COALESCE(s.vat_eur, 0::numeric), 4) AS net_revenue_eur,
    round(COALESCE(s.gross_eur, 0::numeric) - COALESCE(r.refund_amount_eur, 0::numeric) - (COALESCE(s.vat_eur, 0::numeric) - COALESCE(r.refund_vat_eur, 0::numeric)) - (COALESCE(s.referral_eur, 0::numeric) - COALESCE(r.refund_referral_eur, 0::numeric)) - COALESCE(s.fba_fee_eur, 0::numeric) - COALESCE(s.chargeback_eur, 0::numeric) - COALESCE(s.other_fee_eur, 0::numeric) - COALESCE(s.refund_commission_eur, 0::numeric) - COALESCE(s.fbm_shipping_eur, 0::numeric) - (COALESCE(s.cogs_eur, 0::numeric) - COALESCE(r.recovered_cogs_eur, 0::numeric)) - COALESCE(r.return_fee_eur, 0::numeric), 4) AS profit_eur
   FROM sold s
     FULL JOIN refunds r ON r.day = s.day AND r.country_code = s.country_code;

CREATE UNIQUE INDEX mv_overview_country_daily_day_country_uidx ON product.mv_overview_country_daily USING btree (day, country_code);

CREATE VIEW finance.v_schermo_vendite_giorno AS
 SELECT day AS giorno,
    lower(channel) AS canale,
    orders AS ordini,
    gross_eur AS lordo
   FROM product.mv_overview_sales_daily d;

ALTER VIEW finance.v_schermo_vendite_giorno OWNER TO postgres;
REVOKE ALL ON finance.v_schermo_vendite_giorno FROM PUBLIC, anon, authenticated;
GRANT ALL ON finance.v_schermo_vendite_giorno TO service_role;
