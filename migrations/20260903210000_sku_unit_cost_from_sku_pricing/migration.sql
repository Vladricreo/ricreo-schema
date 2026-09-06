-- ============================================================================
-- COGS per SKU: FBA/FBM e varianti non condividono più il costo prodotto.
--
-- inventory_views.v_product_* resta 1 riga/prodotto (C/P/U = worst-case).
-- product.mv_overview_sku_meta.unit_cost_eur legge v_sku_pricing_summary.
-- Se la matview è già allineata (produzione), la migration è un no-op.
-- ============================================================================

DO $$
DECLARE
  meta_def text;
  pnl_sql text;
BEGIN
  SELECT pg_get_viewdef('product.mv_overview_sku_meta'::regclass, true) INTO meta_def;
  IF meta_def LIKE '%v_sku_pricing_summary%' THEN
    RAISE NOTICE 'mv_overview_sku_meta already uses v_sku_pricing_summary';
    RETURN;
  END IF;

  CREATE MATERIALIZED VIEW "product"."mv_overview_sku_meta_sku" AS
  SELECT DISTINCT ON (inv_sku.code)
    inv_sku.code AS sku,
    COALESCE(
      NULLIF(sku_pricing.total_cost, 0),
      NULLIF(pricing.total_cost, 0),
      NULLIF(inv_p.cost, 0)
    ) AS unit_cost_eur,
    inv_p.name AS product_name,
    inv_p."imageUrl" AS image_url,
    COALESCE(inv_sku.asin, inv_p.asin) AS asin
  FROM inventory."Sku" inv_sku
  JOIN inventory."Product" inv_p ON inv_p.id = inv_sku."productId"
  LEFT JOIN inventory_views.v_sku_pricing_summary sku_pricing
    ON sku_pricing.sku_id = inv_sku.id
  LEFT JOIN inventory_views.v_product_pricing_summary pricing
    ON pricing.product_id = inv_p.id
  ORDER BY inv_sku.code, inv_sku."isDefault" DESC, inv_sku."updatedAt" DESC;

  CREATE UNIQUE INDEX "mv_overview_sku_meta_sku_sku_uidx"
    ON "product"."mv_overview_sku_meta_sku" (sku);

  SELECT pg_get_viewdef('product.v_order_line_pnl'::regclass, true) INTO pnl_sql;
  pnl_sql := replace(pnl_sql, 'product.mv_overview_sku_meta', 'product.mv_overview_sku_meta_sku');
  EXECUTE 'CREATE OR REPLACE VIEW product.v_order_line_pnl WITH (security_invoker = true) AS ' || pnl_sql;

  DROP MATERIALIZED VIEW "product"."mv_overview_sku_meta";
  ALTER MATERIALIZED VIEW "product"."mv_overview_sku_meta_sku" RENAME TO "mv_overview_sku_meta";
  ALTER INDEX "product"."mv_overview_sku_meta_sku_sku_uidx" RENAME TO "mv_overview_sku_meta_sku_uidx";

  SELECT pg_get_viewdef('product.v_order_line_pnl'::regclass, true) INTO pnl_sql;
  pnl_sql := replace(pnl_sql, 'product.mv_overview_sku_meta_sku', 'product.mv_overview_sku_meta');
  EXECUTE 'CREATE OR REPLACE VIEW product.v_order_line_pnl WITH (security_invoker = true) AS ' || pnl_sql;

  REFRESH MATERIALIZED VIEW "product"."mv_overview_sales_daily";
  REFRESH MATERIALIZED VIEW "product"."mv_overview_sku_daily";
  REFRESH MATERIALIZED VIEW "product"."mv_overview_fulfillment_daily";
  REFRESH MATERIALIZED VIEW "product"."mv_overview_country_daily";
  REFRESH MATERIALIZED VIEW "product"."mv_sales_analytics_daily";
  REFRESH MATERIALIZED VIEW "product"."mv_sales_analytics_refund_daily";
END $$;
