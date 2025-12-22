-- CreateSchema
CREATE SCHEMA IF NOT EXISTS "inventory_views";

-- ============================================================================
-- VIEW: v_dashboard_finished_stock_by_channel
-- Stock prodotti finiti aggregato per canale (FBM/FBA/CUSTOM)
-- FBA: usa AmazonProduct.quantityTotal (stock Amazon)
-- FBM/CUSTOM: usa Sku.currentStock
-- ============================================================================
CREATE OR REPLACE VIEW "inventory_views"."v_dashboard_finished_stock_by_channel" AS
SELECT
  s."channel"::text AS channel,
  CASE
    WHEN s."channel" = 'FBA' THEN COALESCE(ap."quantityTotal", 0)
    ELSE COALESCE(s."currentStock", 0)
  END AS units
FROM "inventory"."Sku" s
LEFT JOIN "inventory"."AmazonProduct" ap ON ap."skuId" = s."id"
WHERE s."isActive" = true;

-- ============================================================================
-- VIEW: v_dashboard_finished_value_by_channel
-- Valore prodotti finiti per canale con breakdown costo/vendita
-- ============================================================================
CREATE OR REPLACE VIEW "inventory_views"."v_dashboard_finished_value_by_channel" AS
SELECT
  s."channel"::text AS channel,
  SUM(
    CASE
      WHEN s."channel" = 'FBA' THEN COALESCE(ap."quantityTotal", 0)
      ELSE COALESCE(s."currentStock", 0)
    END
  ) AS units,
  SUM(
    CASE
      WHEN s."channel" = 'FBA' THEN COALESCE(ap."quantityTotal", 0)
      ELSE COALESCE(s."currentStock", 0)
    END * COALESCE(p."cost", 0)
  ) AS cost_value,
  SUM(
    CASE
      WHEN s."channel" = 'FBA' THEN COALESCE(ap."quantityTotal", 0)
      ELSE COALESCE(s."currentStock", 0)
    END * COALESCE(p."sellingPrice", p."estimatedPrice", p."cost", 0)
  ) AS sales_value
FROM "inventory"."Sku" s
JOIN "inventory"."Product" p ON p."id" = s."productId"
LEFT JOIN "inventory"."AmazonProduct" ap ON ap."skuId" = s."id"
WHERE s."isActive" = true
GROUP BY s."channel";

-- ============================================================================
-- VIEW: v_dashboard_finished_value_totals
-- Totali valore prodotti finiti
-- ============================================================================
CREATE OR REPLACE VIEW "inventory_views"."v_dashboard_finished_value_totals" AS
SELECT
  COALESCE(SUM(units), 0) AS total_units,
  COALESCE(SUM(cost_value), 0) AS total_cost_value,
  COALESCE(SUM(sales_value), 0) AS total_sales_value
FROM "inventory_views"."v_dashboard_finished_value_by_channel";

-- ============================================================================
-- VIEW: v_dashboard_item_totals
-- Totale articoli in stock (esclusi TOOL)
-- ============================================================================
CREATE OR REPLACE VIEW "inventory_views"."v_dashboard_item_totals" AS
SELECT
  COALESCE(SUM(i."inStock"), 0) AS total_items
FROM "inventory"."Item" i
WHERE i."type" != 'TOOL';

-- ============================================================================
-- VIEW: v_dashboard_low_stock_items
-- Articoli con stock basso (solo SKU, niente nomi)
-- ============================================================================
CREATE OR REPLACE VIEW "inventory_views"."v_dashboard_low_stock_items" AS
SELECT
  i."sku" AS sku,
  (i."inStock" - i."reserved") AS available,
  i."minStock" AS min_stock,
  i."onOrder" AS on_order,
  GREATEST(i."minStock" - (i."inStock" - i."reserved"), 0) AS deficit,
  CASE
    WHEN (i."inStock" - i."reserved") <= 0 THEN 'CRITICAL'
    WHEN (i."inStock" - i."reserved") <= i."minStock" THEN 'WARNING'
    ELSE 'OK'
  END AS severity
FROM "inventory"."Item" i
WHERE i."type" != 'TOOL'
  AND i."minStock" > 0
  AND (i."inStock" - i."reserved") <= i."minStock"
ORDER BY
  CASE
    WHEN (i."inStock" - i."reserved") <= 0 THEN 0
    ELSE 1
  END,
  (i."inStock" - i."reserved") ASC;

-- ============================================================================
-- VIEW: v_dashboard_orders_counts
-- Conteggio ordini produzione e assemblaggio attivi
-- ============================================================================
CREATE OR REPLACE VIEW "inventory_views"."v_dashboard_orders_counts" AS
SELECT
  (
    SELECT COUNT(*)
    FROM "inventory"."ProductOrder"
    WHERE "productionStatus" IN ('READY_TO_PRODUCE', 'PRODUCING', 'NEED_SUPPLIES')
  ) AS pending_production,
  (
    SELECT COUNT(*)
    FROM "inventory"."AssemblyOrder"
    WHERE "status" IN ('READY_TO_ASSEMBLE', 'ASSEMBLY_STARTED')
  ) AS pending_assembly;

-- ============================================================================
-- VIEW: v_dashboard_assembly_hours_by_day
-- Ore assemblaggio per giorno (dagli ultimi 90 giorni)
-- ============================================================================
CREATE OR REPLACE VIEW "inventory_views"."v_dashboard_assembly_hours_by_day" AS
SELECT
  DATE(ao."startedAt") AS day,
  ROUND(
    SUM(
      COALESCE(
        ao."durationSeconds",
        EXTRACT(EPOCH FROM (ao."endedAt" - ao."startedAt"))
      )
    ) / 3600.0,
    2
  ) AS hours,
  SUM(ao."quantityProduced") AS produced_units,
  SUM(ao."quantityScrapped") AS scrapped_units
FROM "inventory"."AssemblyOperation" ao
WHERE ao."startedAt" >= CURRENT_DATE - INTERVAL '90 days'
  AND ao."startedAt" IS NOT NULL
GROUP BY DATE(ao."startedAt")
ORDER BY DATE(ao."startedAt") DESC;

-- ============================================================================
-- VIEW: v_dashboard_item_consumption_daily_by_category
-- Consumo item giornaliero per categoria (Movement type=USO)
-- ============================================================================
CREATE OR REPLACE VIEW "inventory_views"."v_dashboard_item_consumption_daily_by_category" AS
SELECT
  DATE(m."date") AS day,
  COALESCE(c."name", 'Senza categoria') AS category_name,
  SUM(m."quantity") AS quantity_used
FROM "inventory"."Movement" m
LEFT JOIN "inventory"."Item" i ON i."id" = m."itemId"
LEFT JOIN "inventory"."Category" c ON c."id" = i."categoryId"
WHERE m."type" = 'USO'
  AND m."date" >= CURRENT_DATE - INTERVAL '365 days'
GROUP BY DATE(m."date"), COALESCE(c."name", 'Senza categoria')
ORDER BY DATE(m."date") DESC, COALESCE(c."name", 'Senza categoria');

-- ============================================================================
-- VIEW: v_dashboard_sales_daily_best_effort
-- Vendite giornaliere (ibrido: FBA da AmazonSalesData, FBM/CUSTOM da Movement)
-- ============================================================================
CREATE OR REPLACE VIEW "inventory_views"."v_dashboard_sales_daily_best_effort" AS
-- FBA: da AmazonSalesData
SELECT
  asd."date" AS day,
  'FBA'::text AS channel,
  SUM(asd."unitsSold") AS units_sold,
  'AMAZON_SALES_DATA'::text AS source
FROM "inventory"."AmazonSalesData" asd
WHERE asd."date" >= CURRENT_DATE - INTERVAL '365 days'
GROUP BY asd."date"

UNION ALL

-- FBM/CUSTOM: da Movement (type=VENDITA)
SELECT
  DATE(m."date") AS day,
  COALESCE(m."channel"::text, 'FBM') AS channel,
  SUM(m."quantity") AS units_sold,
  'MOVEMENT'::text AS source
FROM "inventory"."Movement" m
WHERE m."type" = 'VENDITA'
  AND m."date" >= CURRENT_DATE - INTERVAL '365 days'
  AND (m."channel" IS NULL OR m."channel" != 'FBA')
GROUP BY DATE(m."date"), COALESCE(m."channel"::text, 'FBM')

ORDER BY day DESC, channel;

-- ============================================================================
-- VIEW: v_dashboard_purchase_orders_leadtime_open
-- Ordini acquisto aperti con calcolo lead time e stato ritardo
-- ============================================================================
CREATE OR REPLACE VIEW "inventory_views"."v_dashboard_purchase_orders_leadtime_open" AS
SELECT
  po."number" AS po_number,
  s."name" AS supplier_name,
  po."orderedAt" AS ordered_at,
  po."orderedAt" + (COALESCE(s."leadTime", 7) * INTERVAL '1 day') AS expected_by,
  EXTRACT(DAY FROM (CURRENT_TIMESTAMP - po."orderedAt"))::integer AS days_open,
  CASE
    WHEN CURRENT_DATE > (po."orderedAt" + (COALESCE(s."leadTime", 7) * INTERVAL '1 day'))::date THEN true
    ELSE false
  END AS is_late,
  po."status"::text AS status
FROM "inventory"."PurchaseOrder" po
JOIN "inventory"."Supplier" s ON s."id" = po."supplierId"
WHERE po."status" != 'RECEIVED'
  AND po."orderedAt" IS NOT NULL
ORDER BY
  CASE WHEN CURRENT_DATE > (po."orderedAt" + (COALESCE(s."leadTime", 7) * INTERVAL '1 day'))::date THEN 0 ELSE 1 END,
  po."orderedAt" ASC;

-- ============================================================================
-- VIEW: v_dashboard_value_by_category
-- Valore per categoria (solo costo, per grafico)
-- ============================================================================
CREATE OR REPLACE VIEW "inventory_views"."v_dashboard_value_by_category" AS
SELECT
  COALESCE(c."name", 'Senza categoria') AS category_name,
  SUM(i."inStock") AS items_count,
  SUM(
    i."inStock" * COALESCE(
      CASE
        WHEN i."properties"->>'cost' IS NOT NULL
        THEN (i."properties"->>'cost')::numeric
        ELSE 0
      END,
      0
    )
  ) AS cost_value
FROM "inventory"."Item" i
LEFT JOIN "inventory"."Category" c ON c."id" = i."categoryId"
WHERE i."type" != 'TOOL'
GROUP BY COALESCE(c."name", 'Senza categoria')
HAVING SUM(i."inStock") > 0
ORDER BY cost_value DESC;

