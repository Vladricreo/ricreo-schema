-- ============================================================================
-- P&L: `mv_overview_sku_meta.unit_cost_eur` per SKU, non per prodotto.
--
-- Definizione canonica: prisma/custom_migrations/sql/overview_sku_meta_per_sku_cost.sql
-- Dopo il deploy: REFRESH CONCURRENTLY delle matview P&L, oppure:
--   node scripts/apply-sku-cost-views.mjs --refresh-only
--
-- Se lo applichi fuori da Prisma:
--   bunx prisma migrate resolve --applied 20260903170000_overview_sku_meta_per_sku_cost
-- ============================================================================

DO $$
DECLARE
  view_sql text;
BEGIN
  -- Gia' migrata: pulisce eventuale matview temporanea e esce.
  IF to_regclass('product.mv_overview_sku_meta') IS NOT NULL
     AND pg_get_viewdef('product.mv_overview_sku_meta'::regclass, true)
         LIKE '%v_sku_pricing_summary%'
  THEN
    DROP MATERIALIZED VIEW IF EXISTS "product"."mv_overview_sku_meta_new";
    RAISE NOTICE 'mv_overview_sku_meta usa gia'' v_sku_pricing_summary: swap saltato.';
    RETURN;
  END IF;

  IF to_regclass('product.mv_overview_sku_meta_new') IS NULL THEN
    EXECUTE $mv$
      CREATE MATERIALIZED VIEW "product"."mv_overview_sku_meta_new" AS
      SELECT DISTINCT ON (inv_sku.code)
        inv_sku.code AS sku,
        COALESCE(
          NULLIF(sku_pricing.total_cost, 0::numeric),
          NULLIF(pricing.total_cost, 0::numeric),
          NULLIF(inv_p.cost, 0::numeric)
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
      ORDER BY inv_sku.code, inv_sku."isDefault" DESC, inv_sku."updatedAt" DESC
    $mv$;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'product'
      AND c.relname = 'mv_overview_sku_meta_new_sku_uidx'
  ) THEN
    EXECUTE 'CREATE UNIQUE INDEX mv_overview_sku_meta_new_sku_uidx
             ON "product"."mv_overview_sku_meta_new" USING btree (sku)';
  END IF;

  -- Ripunta `v_order_line_pnl` sulla matview nuova. `pg_get_viewdef` evita di
  -- duplicare il corpo della vista (cambia spesso) e tiene le stesse colonne,
  -- quindi `v_order_line_refund` e le matview P&L restano valide.
  SELECT pg_get_viewdef('product.v_order_line_pnl'::regclass, true)
    INTO view_sql;

  IF view_sql NOT LIKE '%mv_overview_sku_meta_new%' THEN
    view_sql := replace(
      view_sql,
      '"product"."mv_overview_sku_meta"',
      '"product"."mv_overview_sku_meta_new"'
    );
    view_sql := replace(
      view_sql,
      'product.mv_overview_sku_meta',
      'product.mv_overview_sku_meta_new'
    );

    EXECUTE 'CREATE OR REPLACE VIEW product.v_order_line_pnl WITH (security_invoker = true) AS '
      || view_sql;
  END IF;

  IF to_regclass('product.mv_overview_sku_meta') IS NOT NULL THEN
    DROP MATERIALIZED VIEW "product"."mv_overview_sku_meta";
  END IF;

  ALTER MATERIALIZED VIEW "product"."mv_overview_sku_meta_new"
    RENAME TO mv_overview_sku_meta;

  IF EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'product'
      AND c.relname = 'mv_overview_sku_meta_new_sku_uidx'
  ) THEN
    ALTER INDEX "product"."mv_overview_sku_meta_new_sku_uidx"
      RENAME TO mv_overview_sku_meta_sku_uidx;
  END IF;
END $$;
