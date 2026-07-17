-- ============================================================================
-- ITEM CONSUMPTION ANALYTICS VIEWS
-- Vista di dettaglio consumo per singolo Item: serie giornaliera, riepilogo
-- (30/90 giorni) e stagionalità mensile. Alimentano la pagina
-- "Ordini > Consumi" (grafici per item, filtri categoria/ricerca/periodo).
--
-- Tipi movimento considerati "consumo": USO, VENDITA, TRASH
-- (allineato a v_dashboard_consumption_by_category_period / v_dashboard_seasonality)
-- Esclusi: Item di tipo TOOL (utensili, non consumo di magazzino)
--
-- Copia tracciata (via prisma migrate) di
-- prisma/custom_migrations/sql/item_consumption_analytics_views.sql
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS "inventory_views";

-- ============================================================================
-- VIEW: v_item_consumption_daily
-- Serie storica giornaliera di consumo per Item (una riga per item+giorno con consumo > 0)
-- ============================================================================
CREATE OR REPLACE VIEW "inventory_views"."v_item_consumption_daily" AS
SELECT
  m."itemId" AS item_id,
  DATE(m."date") AS day,
  SUM(m."quantity")::BIGINT AS consumed_quantity
FROM "inventory"."Movement" m
JOIN "inventory"."Item" i ON i."id" = m."itemId"
WHERE m."itemId" IS NOT NULL
  AND m."type" IN ('USO', 'VENDITA', 'TRASH')
  AND i."type" != 'TOOL'
GROUP BY m."itemId", DATE(m."date");

-- ============================================================================
-- VIEW: v_item_consumption_summary
-- Riepilogo consumo per Item: totali/medie 30gg e 90gg, categoria, stock attuale.
-- Una riga per Item (anche senza movimenti, per poterlo comunque elencare/filtrare).
-- ============================================================================
CREATE OR REPLACE VIEW "inventory_views"."v_item_consumption_summary" AS
WITH consumo_30d AS (
  SELECT item_id, SUM(consumed_quantity)::BIGINT AS total_30d, COUNT(*)::INT AS days_with_data_30d
  FROM "inventory_views"."v_item_consumption_daily"
  WHERE day >= CURRENT_DATE - INTERVAL '30 days'
  GROUP BY item_id
),
consumo_90d AS (
  SELECT item_id, SUM(consumed_quantity)::BIGINT AS total_90d
  FROM "inventory_views"."v_item_consumption_daily"
  WHERE day >= CURRENT_DATE - INTERVAL '90 days'
  GROUP BY item_id
),
movimenti_30d AS (
  SELECT m."itemId" AS item_id, COUNT(*)::INT AS movement_count_30d, MAX(m."date") AS last_movement_date
  FROM "inventory"."Movement" m
  WHERE m."itemId" IS NOT NULL
    AND m."type" IN ('USO', 'VENDITA', 'TRASH')
    AND m."date" >= CURRENT_DATE - INTERVAL '30 days'
  GROUP BY m."itemId"
)
SELECT
  i."id" AS item_id,
  i."name" AS item_name,
  i."sku" AS item_sku,
  i."type"::text AS item_type,
  COALESCE(c."name", 'Senza categoria') AS category_name,
  i."categoryId" AS category_id,
  i."inStock" AS in_stock,
  COALESCE(c30.total_30d, 0)::BIGINT AS total_30d,
  COALESCE(c90.total_90d, 0)::BIGINT AS total_90d,
  ROUND(COALESCE(c30.total_30d, 0) / 30.0, 2) AS avg_daily_30d,
  ROUND(COALESCE(c90.total_90d, 0) / 90.0, 2) AS avg_daily_90d,
  COALESCE(mv.movement_count_30d, 0) AS movement_count_30d,
  mv.last_movement_date AS last_movement_date
FROM "inventory"."Item" i
LEFT JOIN "inventory"."Category" c ON c."id" = i."categoryId"
LEFT JOIN consumo_30d c30 ON c30.item_id = i."id"
LEFT JOIN consumo_90d c90 ON c90.item_id = i."id"
LEFT JOIN movimenti_30d mv ON mv.item_id = i."id"
WHERE i."type" != 'TOOL';

-- ============================================================================
-- VIEW: v_item_consumption_seasonality
-- Stagionalità per Item: consumo medio giornaliero per mese dell'anno (1=Gen..12=Dic)
-- aggregato su tutti gli anni disponibili. Stesso pattern di v_dashboard_seasonality
-- ma a livello di singolo item.
-- ============================================================================
CREATE OR REPLACE VIEW "inventory_views"."v_item_consumption_seasonality" AS
SELECT
  item_id,
  EXTRACT(MONTH FROM day)::INT AS month_of_year,
  ROUND(AVG(consumed_quantity), 2) AS avg_daily_consumption,
  SUM(consumed_quantity)::BIGINT AS total_consumption,
  COUNT(*)::BIGINT AS days_with_data
FROM "inventory_views"."v_item_consumption_daily"
GROUP BY item_id, EXTRACT(MONTH FROM day)
ORDER BY item_id, month_of_year;
