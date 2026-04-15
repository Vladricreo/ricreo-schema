-- Consumption demand views (item + product part BUY)
-- Copia allineata a prisma/migrations/sql/consumption_demand_views.sql

CREATE SCHEMA IF NOT EXISTS "inventory_views";

CREATE OR REPLACE VIEW inventory_views.v_item_consumption_demand AS
WITH params AS (
    SELECT GREATEST(
        COALESCE(
            (
                SELECT
                    CASE
                        WHEN s.value IS NULL THEN 30
                        WHEN jsonb_typeof(s.value::jsonb) = 'number' THEN (s.value::text)::INT
                        WHEN (s.value::jsonb) ? 'days' THEN (s.value::jsonb->>'days')::INT
                        WHEN s.value::text ~ '^[0-9]+$' THEN s.value::text::INT
                        ELSE 30
                    END
                FROM inventory."Settings" s
                WHERE s.name = 'STOCK_THRESHOLD'
                LIMIT 1
            ),
            30
        ),
        1
    ) AS threshold_days
),
per_item_movements AS (
    SELECT
        m."itemId" AS item_id,
        m.quantity,
        m.date,
        (CURRENT_DATE - (m.date AT TIME ZONE 'UTC')::DATE)::INT AS days_ago
    FROM inventory."Movement" m
    CROSS JOIN params p
    WHERE m."itemId" IS NOT NULL
      AND m.type IN ('USO', 'VENDITA')
      AND m.date >= CURRENT_TIMESTAMP - (p.threshold_days::TEXT || ' days')::INTERVAL
),
bucket_sums AS (
    SELECT
        item_id,
        SUM(CASE WHEN days_ago >= 0 AND days_ago < 8 THEN quantity ELSE 0 END)::BIGINT AS s0,
        SUM(CASE WHEN days_ago >= 8 AND days_ago < 31 THEN quantity ELSE 0 END)::BIGINT AS s1,
        SUM(CASE WHEN days_ago >= 31 THEN quantity ELSE 0 END)::BIGINT AS s2,
        COUNT(*)::INT AS movement_count,
        SUM(quantity)::BIGINT AS total_consumption,
        (CURRENT_DATE - MIN((date AT TIME ZONE 'UTC')::DATE) + 1)::INT AS oldest_age_days
    FROM per_item_movements
    GROUP BY item_id
),
weighted_raw AS (
    SELECT
        bs.item_id,
        bs.movement_count,
        bs.total_consumption,
        bs.oldest_age_days,
        (
            (CASE WHEN bs.s0 > 0 THEN (bs.s0::NUMERIC / GREATEST(1, LEAST(8, bs.oldest_age_days)::NUMERIC)) * 3 ELSE 0::NUMERIC END)
          + (CASE WHEN bs.s1 > 0 THEN (bs.s1::NUMERIC / GREATEST(1, (LEAST(31, bs.oldest_age_days) - 8))::NUMERIC) * 2 ELSE 0::NUMERIC END)
          + (CASE WHEN bs.s2 > 0 THEN (bs.s2::NUMERIC / GREATEST(1, (bs.oldest_age_days - 31))::NUMERIC) * 1 ELSE 0::NUMERIC END)
        ) AS weighted_numerator,
        (
            (CASE WHEN bs.s0 > 0 THEN 3 ELSE 0 END)
          + (CASE WHEN bs.s1 > 0 THEN 2 ELSE 0 END)
          + (CASE WHEN bs.s2 > 0 THEN 1 ELSE 0 END)
        )::NUMERIC AS weighted_denominator,
        CASE
            WHEN bs.movement_count = 0 OR bs.total_consumption <= 0 THEN 0::NUMERIC
            ELSE bs.total_consumption::NUMERIC / GREATEST(1, bs.oldest_age_days::NUMERIC)
        END AS daily_simple,
        (
            bs.total_consumption > 0
            AND bs.oldest_age_days >= 7
            AND bs.movement_count >= 3
        ) AS is_reliable
    FROM bucket_sums bs
),
weighted_calc AS (
    SELECT
        wr.item_id,
        wr.movement_count,
        wr.total_consumption,
        wr.oldest_age_days AS effective_days,
        wr.daily_simple AS daily_consumption_simple,
        wr.is_reliable,
        CASE
            WHEN wr.is_reliable AND wr.weighted_denominator > 0 THEN wr.weighted_numerator / wr.weighted_denominator
            ELSE 0::NUMERIC
        END AS daily_consumption_weighted
    FROM weighted_raw wr
),
pending_assembly AS (
    SELECT
        ao.id,
        ao."productId" AS product_id,
        ao."skuId" AS sku_id,
        GREATEST(ao."quantityToAssemble" - ao."quantityAssembled", 0)::NUMERIC AS remain
    FROM inventory."AssemblyOrder" ao
    WHERE ao.status NOT IN ('ASSEMBLY_COMPLETED', 'CANCELLED')
      AND GREATEST(ao."quantityToAssemble" - ao."quantityAssembled", 0) > 0
),
assembly_lines AS (
    SELECT ri.item_id, SUM(c.quantity * pa.remain)::NUMERIC AS qty
    FROM pending_assembly pa
    JOIN inventory."ProductToComponent" c
      ON c."productId" = pa.product_id
     AND c.priority = 0
     AND (c."skuId" IS NULL OR c."skuId" = pa.sku_id)
    JOIN inventory_views.v_item_spec_resolved ri ON ri.spec_id = c."itemSpecId"
    GROUP BY ri.item_id
    UNION ALL
    SELECT ri.item_id, SUM(p.quantity * pa.remain)::NUMERIC AS qty
    FROM pending_assembly pa
    JOIN inventory."ProductToPackage" p
      ON p."productId" = pa.product_id
     AND p.priority = 0
     AND (p."skuId" IS NULL OR p."skuId" = pa.sku_id)
    JOIN inventory_views.v_item_spec_resolved ri ON ri.spec_id = p."itemSpecId"
    GROUP BY ri.item_id
    UNION ALL
    SELECT ri.item_id, SUM(u.quantity * pa.remain)::NUMERIC AS qty
    FROM pending_assembly pa
    JOIN inventory."ProductToUtility" u
      ON u."productId" = pa.product_id
     AND u.priority = 0
     AND (u."skuId" IS NULL OR u."skuId" = pa.sku_id)
    JOIN inventory_views.v_item_spec_resolved ri ON ri.spec_id = u."itemSpecId"
    GROUP BY ri.item_id
),
assembly_demand_by_item AS (
    SELECT item_id, SUM(qty)::NUMERIC AS demand_qty
    FROM assembly_lines
    GROUP BY item_id
),
category_annual AS (
    SELECT
        s.category_name,
        SUM(s.total_consumption)::NUMERIC / NULLIF(SUM(s.days_with_data), 0) AS avg_daily_year
    FROM inventory_views.v_dashboard_seasonality s
    GROUP BY s.category_name
),
item_category AS (
    SELECT
        i.id AS item_id,
        COALESCE(c.name, 'Senza categoria') AS category_name
    FROM inventory."Item" i
    LEFT JOIN inventory."Category" c ON c.id = i."categoryId"
),
seasonal AS (
    SELECT
        ic.item_id,
        LEAST(
            2::NUMERIC,
            GREATEST(
                0.5::NUMERIC,
                COALESCE(
                    cm.avg_daily_consumption::NUMERIC / NULLIF(ya.avg_daily_year, 0),
                    1::NUMERIC
                )
            )
        ) AS seasonal_factor
    FROM item_category ic
    LEFT JOIN category_annual ya ON ya.category_name = ic.category_name
    LEFT JOIN inventory_views.v_dashboard_seasonality cm
      ON cm.category_name = ic.category_name
     AND cm.month_of_year = EXTRACT(MONTH FROM CURRENT_DATE)::INT
)
SELECT
    i.id AS item_id,
    COALESCE(wc.daily_consumption_weighted, 0)::NUMERIC(14, 6) AS daily_consumption_weighted,
    COALESCE(wc.daily_consumption_simple, 0)::NUMERIC(14, 6) AS daily_consumption_simple,
    COALESCE(wc.is_reliable, FALSE) AS is_reliable,
    COALESCE(wc.movement_count, 0) AS movement_count,
    COALESCE(wc.effective_days, 0) AS effective_days,
    COALESCE(wc.total_consumption, 0)::BIGINT AS total_consumption,
    COALESCE(rs.reserved_quantity, 0) AS demand_from_production,
    COALESCE(CEIL(ad.demand_qty), 0)::INT AS demand_from_assembly,
    COALESCE(se.seasonal_factor, 1::NUMERIC)::NUMERIC(8, 4) AS seasonal_factor,
    (
        COALESCE(wc.daily_consumption_weighted, 0::NUMERIC)
        * COALESCE(se.seasonal_factor, 1::NUMERIC)
    )::NUMERIC(14, 6) AS adjusted_daily_consumption
FROM inventory."Item" i
LEFT JOIN weighted_calc wc ON wc.item_id = i.id
LEFT JOIN inventory_views.v_item_reserved_stock rs ON rs.item_id = i.id
LEFT JOIN assembly_demand_by_item ad ON ad.item_id = i.id
LEFT JOIN seasonal se ON se.item_id = i.id;

CREATE OR REPLACE VIEW inventory_views.v_product_part_consumption_demand AS
WITH params AS (
    SELECT GREATEST(
        COALESCE(
            (
                SELECT
                    CASE
                        WHEN s.value IS NULL THEN 30
                        WHEN jsonb_typeof(s.value::jsonb) = 'number' THEN (s.value::text)::INT
                        WHEN (s.value::jsonb) ? 'days' THEN (s.value::jsonb->>'days')::INT
                        WHEN s.value::text ~ '^[0-9]+$' THEN s.value::text::INT
                        ELSE 30
                    END
                FROM inventory."Settings" s
                WHERE s.name = 'STOCK_THRESHOLD'
                LIMIT 1
            ),
            30
        ),
        1
    ) AS threshold_days
),
buy_parts AS (
    SELECT pp.id AS product_part_id, pp."productId" AS product_id
    FROM inventory."ProductPart" pp
    WHERE pp."sourceType" = 'BUY'
),
per_part_movements AS (
    SELECT
        m."productPartId" AS product_part_id,
        m.quantity,
        m.date,
        (CURRENT_DATE - (m.date AT TIME ZONE 'UTC')::DATE)::INT AS days_ago
    FROM inventory."Movement" m
    INNER JOIN buy_parts bp ON bp.product_part_id = m."productPartId"
    CROSS JOIN params p
    WHERE m."productPartId" IS NOT NULL
      AND m.type IN ('USO', 'VENDITA')
      AND m.date >= CURRENT_TIMESTAMP - (p.threshold_days::TEXT || ' days')::INTERVAL
),
bucket_sums AS (
    SELECT
        product_part_id,
        SUM(CASE WHEN days_ago >= 0 AND days_ago < 8 THEN quantity ELSE 0 END)::BIGINT AS s0,
        SUM(CASE WHEN days_ago >= 8 AND days_ago < 31 THEN quantity ELSE 0 END)::BIGINT AS s1,
        SUM(CASE WHEN days_ago >= 31 THEN quantity ELSE 0 END)::BIGINT AS s2,
        COUNT(*)::INT AS movement_count,
        SUM(quantity)::BIGINT AS total_consumption,
        (CURRENT_DATE - MIN((date AT TIME ZONE 'UTC')::DATE) + 1)::INT AS oldest_age_days
    FROM per_part_movements
    GROUP BY product_part_id
),
weighted_raw AS (
    SELECT
        bs.product_part_id,
        bs.movement_count,
        bs.total_consumption,
        bs.oldest_age_days,
        (
            (CASE WHEN bs.s0 > 0 THEN (bs.s0::NUMERIC / GREATEST(1, LEAST(8, bs.oldest_age_days)::NUMERIC)) * 3 ELSE 0::NUMERIC END)
          + (CASE WHEN bs.s1 > 0 THEN (bs.s1::NUMERIC / GREATEST(1, (LEAST(31, bs.oldest_age_days) - 8))::NUMERIC) * 2 ELSE 0::NUMERIC END)
          + (CASE WHEN bs.s2 > 0 THEN (bs.s2::NUMERIC / GREATEST(1, (bs.oldest_age_days - 31))::NUMERIC) * 1 ELSE 0::NUMERIC END)
        ) AS weighted_numerator,
        (
            (CASE WHEN bs.s0 > 0 THEN 3 ELSE 0 END)
          + (CASE WHEN bs.s1 > 0 THEN 2 ELSE 0 END)
          + (CASE WHEN bs.s2 > 0 THEN 1 ELSE 0 END)
        )::NUMERIC AS weighted_denominator,
        CASE
            WHEN bs.movement_count = 0 OR bs.total_consumption <= 0 THEN 0::NUMERIC
            ELSE bs.total_consumption::NUMERIC / GREATEST(1, bs.oldest_age_days::NUMERIC)
        END AS daily_simple,
        (
            bs.total_consumption > 0
            AND bs.oldest_age_days >= 7
            AND bs.movement_count >= 3
        ) AS is_reliable
    FROM bucket_sums bs
),
weighted_calc AS (
    SELECT
        wr.product_part_id,
        wr.movement_count,
        wr.total_consumption,
        wr.oldest_age_days AS effective_days,
        wr.daily_simple AS daily_consumption_simple,
        wr.is_reliable,
        CASE
            WHEN wr.is_reliable AND wr.weighted_denominator > 0 THEN wr.weighted_numerator / wr.weighted_denominator
            ELSE 0::NUMERIC
        END AS daily_consumption_weighted
    FROM weighted_raw wr
),
part_product_category AS (
    SELECT
        bp.product_part_id,
        COALESCE(c.name, 'Senza categoria') AS category_name
    FROM buy_parts bp
    JOIN inventory."Product" pr ON pr.id = bp.product_id
    LEFT JOIN inventory."Item" pi ON pi.id = pr."itemId"
    LEFT JOIN inventory."Category" c ON c.id = pi."categoryId"
),
category_annual AS (
    SELECT
        s.category_name,
        SUM(s.total_consumption)::NUMERIC / NULLIF(SUM(s.days_with_data), 0) AS avg_daily_year
    FROM inventory_views.v_dashboard_seasonality s
    GROUP BY s.category_name
),
seasonal AS (
    SELECT
        ppc.product_part_id,
        LEAST(
            2::NUMERIC,
            GREATEST(
                0.5::NUMERIC,
                COALESCE(
                    cm.avg_daily_consumption::NUMERIC / NULLIF(ya.avg_daily_year, 0),
                    1::NUMERIC
                )
            )
        ) AS seasonal_factor
    FROM part_product_category ppc
    LEFT JOIN category_annual ya ON ya.category_name = ppc.category_name
    LEFT JOIN inventory_views.v_dashboard_seasonality cm
      ON cm.category_name = ppc.category_name
     AND cm.month_of_year = EXTRACT(MONTH FROM CURRENT_DATE)::INT
)
SELECT
    bp.product_part_id,
    COALESCE(wc.daily_consumption_weighted, 0)::NUMERIC(14, 6) AS daily_consumption_weighted,
    COALESCE(wc.daily_consumption_simple, 0)::NUMERIC(14, 6) AS daily_consumption_simple,
    COALESCE(wc.is_reliable, FALSE) AS is_reliable,
    COALESCE(wc.movement_count, 0) AS movement_count,
    COALESCE(wc.effective_days, 0) AS effective_days,
    COALESCE(wc.total_consumption, 0)::BIGINT AS total_consumption,
    0::INT AS demand_from_production,
    0::INT AS demand_from_assembly,
    COALESCE(se.seasonal_factor, 1::NUMERIC)::NUMERIC(8, 4) AS seasonal_factor,
    (
        COALESCE(wc.daily_consumption_weighted, 0::NUMERIC)
        * COALESCE(se.seasonal_factor, 1::NUMERIC)
    )::NUMERIC(14, 6) AS adjusted_daily_consumption
FROM buy_parts bp
LEFT JOIN weighted_calc wc ON wc.product_part_id = bp.product_part_id
LEFT JOIN seasonal se ON se.product_part_id = bp.product_part_id;
