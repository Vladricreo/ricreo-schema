-- Overlay stock famiglie ItemSpec + consumo aggregato per riordino.
-- I grammi delle spool aperte NON vengono scritti in Item.inStock.

CREATE OR REPLACE VIEW inventory_views.v_item_open_spool_grams AS
SELECT
  fs."itemId" AS item_id,
  i."itemSpecId" AS spec_id,
  SUM(GREATEST(fs."remainingWeight", 0))::NUMERIC(14, 2) AS remaining_grams
FROM "print-farm"."FilamentSpool" fs
JOIN inventory."Item" i ON i.id = fs."itemId"
WHERE fs.status = 'ACTIVE'
  AND fs."remainingWeight" > 0
GROUP BY fs."itemId", i."itemSpecId";

CREATE OR REPLACE VIEW inventory_views.v_item_spec_stock_position AS
WITH member_stock AS (
  SELECT
    i."itemSpecId" AS spec_id,
    SUM(GREATEST(COALESCE(i."inStock", 0), 0))::INT AS sealed_units,
    SUM(
      GREATEST(COALESCE(i."inStock", 0), 0)::NUMERIC
      * (COALESCE(i.weight, sw.weight, 0)::NUMERIC * 1000)
    )::NUMERIC(14, 2) AS sealed_grams
  FROM inventory."Item" i
  LEFT JOIN inventory."StandardWeight" sw ON sw.id = i."standardWeightId"
  WHERE i."itemSpecId" IS NOT NULL
  GROUP BY i."itemSpecId"
),
open_by_spec AS (
  SELECT
    spec_id,
    SUM(remaining_grams)::NUMERIC(14, 2) AS open_grams
  FROM inventory_views.v_item_open_spool_grams
  WHERE spec_id IS NOT NULL
  GROUP BY spec_id
),
preferred AS (
  SELECT
    r.spec_id,
    r.item_id AS preferred_item_id,
    (COALESCE(i.weight, sw.weight, 0)::NUMERIC * 1000) AS preferred_weight_g,
    s.type AS item_type
  FROM inventory_views.v_item_spec_resolved r
  JOIN inventory."ItemSpec" s ON s.id = r.spec_id
  LEFT JOIN inventory."Item" i ON i.id = r.item_id
  LEFT JOIN inventory."StandardWeight" sw ON sw.id = i."standardWeightId"
)
SELECT
  s.id AS spec_id,
  p.preferred_item_id,
  s.type::TEXT AS item_type,
  COALESCE(ms.sealed_units, 0)::INT AS sealed_units,
  COALESCE(ms.sealed_grams, 0)::NUMERIC(14, 2) AS sealed_grams,
  COALESCE(os.open_grams, 0)::NUMERIC(14, 2) AS open_grams,
  COALESCE(p.preferred_weight_g, 0)::NUMERIC(14, 2) AS preferred_weight_g,
  CASE
    WHEN s.type = 'MATERIAL' THEN
      CASE
        WHEN COALESCE(p.preferred_weight_g, 0) > 0 THEN
          (COALESCE(ms.sealed_grams, 0) + COALESCE(os.open_grams, 0))
            / p.preferred_weight_g
        ELSE COALESCE(ms.sealed_units, 0)::NUMERIC
      END
    ELSE COALESCE(ms.sealed_units, 0)::NUMERIC
  END::NUMERIC(14, 6) AS effective_units,
  CASE
    WHEN s.type = 'MATERIAL' AND COALESCE(p.preferred_weight_g, 0) > 0 THEN
      COALESCE(os.open_grams, 0) / p.preferred_weight_g
    ELSE 0::NUMERIC
  END::NUMERIC(14, 6) AS open_equivalent_units,
  (s.type = 'MATERIAL' AND COALESCE(p.preferred_weight_g, 0) <= 0) AS weight_missing
FROM inventory."ItemSpec" s
LEFT JOIN preferred p ON p.spec_id = s.id
LEFT JOIN member_stock ms ON ms.spec_id = s.id
LEFT JOIN open_by_spec os ON os.spec_id = s.id;

CREATE OR REPLACE VIEW inventory_views.v_item_spec_consumption_demand AS
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
per_spec_movements AS (
    SELECT
        COALESCE(m."itemSpecId", i."itemSpecId") AS spec_id,
        m.quantity,
        m.date,
        (CURRENT_DATE - (m.date AT TIME ZONE 'UTC')::DATE)::INT AS days_ago
    FROM inventory."Movement" m
    LEFT JOIN inventory."Item" i ON i.id = m."itemId"
    CROSS JOIN params p
    WHERE COALESCE(m."itemSpecId", i."itemSpecId") IS NOT NULL
      AND m.type IN ('USO', 'VENDITA', 'TRASH')
      AND m.date >= CURRENT_TIMESTAMP - (p.threshold_days::TEXT || ' days')::INTERVAL
),
bucket_sums AS (
    SELECT
        spec_id,
        SUM(CASE WHEN days_ago >= 0 AND days_ago < 8 THEN quantity ELSE 0 END)::BIGINT AS s0,
        SUM(CASE WHEN days_ago >= 8 AND days_ago < 31 THEN quantity ELSE 0 END)::BIGINT AS s1,
        SUM(CASE WHEN days_ago >= 31 THEN quantity ELSE 0 END)::BIGINT AS s2,
        COUNT(*)::INT AS movement_count,
        SUM(quantity)::BIGINT AS total_consumption,
        (CURRENT_DATE - MIN((date AT TIME ZONE 'UTC')::DATE) + 1)::INT AS oldest_age_days
    FROM per_spec_movements
    GROUP BY spec_id
),
weighted_raw AS (
    SELECT
        bs.spec_id,
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
        wr.spec_id,
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
    SELECT c."itemSpecId" AS spec_id, SUM(c.quantity * pa.remain)::NUMERIC AS qty
    FROM pending_assembly pa
    JOIN inventory."ProductToComponent" c
      ON c."productId" = pa.product_id
     AND c.priority = 0
     AND (c."skuId" IS NULL OR c."skuId" = pa.sku_id)
    WHERE c."itemSpecId" IS NOT NULL
    GROUP BY c."itemSpecId"
    UNION ALL
    SELECT p."itemSpecId" AS spec_id, SUM(p.quantity * pa.remain)::NUMERIC AS qty
    FROM pending_assembly pa
    JOIN inventory."ProductToPackage" p
      ON p."productId" = pa.product_id
     AND p.priority = 0
     AND (p."skuId" IS NULL OR p."skuId" = pa.sku_id)
    WHERE p."itemSpecId" IS NOT NULL
    GROUP BY p."itemSpecId"
    UNION ALL
    SELECT u."itemSpecId" AS spec_id, SUM(u.quantity * pa.remain)::NUMERIC AS qty
    FROM pending_assembly pa
    JOIN inventory."ProductToUtility" u
      ON u."productId" = pa.product_id
     AND u.priority = 0
     AND (u."skuId" IS NULL OR u."skuId" = pa.sku_id)
    WHERE u."itemSpecId" IS NOT NULL
    GROUP BY u."itemSpecId"
),
assembly_demand_by_spec AS (
    SELECT spec_id, SUM(qty)::NUMERIC AS demand_qty
    FROM assembly_lines
    GROUP BY spec_id
),
active_product_orders AS (
    SELECT
        o.id AS product_order_id,
        o."productId" AS product_id,
        o."skuId" AS sku_id,
        o."quantityToProduce" AS quantity_to_produce,
        GREATEST(o."quantityToProduce" - o."quantityProduced", 0) AS quantity_remaining
    FROM inventory."ProductOrder" o
    WHERE o."productionStatus" IN ('READY_TO_PRODUCE', 'PRODUCING', 'NEED_SUPPLIES')
),
required_parts_remaining AS (
    SELECT
        popp."productOrderId" AS product_order_id,
        popp."productPartId" AS product_part_id,
        GREATEST(popp.quantity - popp."quantityProduced", 0)::NUMERIC AS part_qty_remaining
    FROM inventory."ProductOrderProductPart" popp
    UNION ALL
    SELECT
        apo.product_order_id,
        pp.id AS product_part_id,
        (pp."quantityNeeded" * apo.quantity_remaining)::NUMERIC AS part_qty_remaining
    FROM active_product_orders apo
    JOIN inventory."ProductPart" pp ON pp."productId" = apo.product_id
    WHERE apo.quantity_to_produce > 0
      AND NOT EXISTS (
        SELECT 1
        FROM inventory."ProductOrderProductPart" x
        WHERE x."productOrderId" = apo.product_order_id
      )
),
production_lines AS (
    SELECT
        c."itemSpecId" AS spec_id,
        'Component'::TEXT AS kind,
        (c.quantity * apo.quantity_remaining)::NUMERIC AS qty,
        0 AS bom_priority
    FROM active_product_orders apo
    JOIN inventory."ProductToComponent" c
      ON c."productId" = apo.product_id
     AND c.priority = 0
     AND (c."skuId" IS NULL OR c."skuId" = apo.sku_id)
    WHERE apo.quantity_to_produce > 0
      AND c."itemSpecId" IS NOT NULL
    UNION ALL
    SELECT
        p."itemSpecId" AS spec_id,
        'Packaging'::TEXT AS kind,
        (p.quantity * apo.quantity_remaining)::NUMERIC AS qty,
        0 AS bom_priority
    FROM active_product_orders apo
    JOIN inventory."ProductToPackage" p
      ON p."productId" = apo.product_id
     AND p.priority = 0
     AND (p."skuId" IS NULL OR p."skuId" = apo.sku_id)
    WHERE apo.quantity_to_produce > 0
      AND p."itemSpecId" IS NOT NULL
    UNION ALL
    SELECT
        u."itemSpecId" AS spec_id,
        'Utility'::TEXT AS kind,
        (u.quantity * apo.quantity_remaining)::NUMERIC AS qty,
        0 AS bom_priority
    FROM active_product_orders apo
    JOIN inventory."ProductToUtility" u
      ON u."productId" = apo.product_id
     AND u.priority = 0
     AND (u."skuId" IS NULL OR u."skuId" = apo.sku_id)
    WHERE apo.quantity_to_produce > 0
      AND u."itemSpecId" IS NOT NULL
    UNION ALL
    SELECT
        mb."materialSpecId" AS spec_id,
        'Material'::TEXT AS kind,
        (mb."usedWeight" * rp.part_qty_remaining)::NUMERIC AS qty,
        mb.priority AS bom_priority
    FROM required_parts_remaining rp
    JOIN inventory."ProductPart" pp ON pp.id = rp.product_part_id
    JOIN inventory."ProductPartMaterial" mb
      ON mb."productPartId" = rp.product_part_id
    WHERE pp."sourceType" = 'MAKE'
      AND mb."materialSpecId" IS NOT NULL
),
production_demand AS (
    SELECT spec_id, kind, SUM(qty) AS total_needed
    FROM production_lines
    WHERE kind <> 'Material' OR bom_priority = 0
    GROUP BY spec_id, kind
),
production_demand_by_spec AS (
    SELECT
        pd.spec_id,
        SUM(
            CASE
                WHEN pd.kind = 'Material' THEN
                    CASE
                        WHEN COALESCE(pos.preferred_weight_g, 0) > 0 THEN
                            CEIL(pd.total_needed / pos.preferred_weight_g)
                        ELSE 0
                    END
                ELSE pd.total_needed
            END
        )::INT AS demand_qty
    FROM production_demand pd
    LEFT JOIN inventory_views.v_item_spec_stock_position pos ON pos.spec_id = pd.spec_id
    GROUP BY pd.spec_id
),
category_annual AS (
    SELECT
        s.category_name,
        SUM(s.total_consumption)::NUMERIC / NULLIF(SUM(s.days_with_data), 0) AS avg_daily_year
    FROM inventory_views.v_dashboard_seasonality s
    GROUP BY s.category_name
),
spec_category AS (
    SELECT
        spec.id AS spec_id,
        COALESCE(c.name, 'Senza categoria') AS category_name
    FROM inventory."ItemSpec" spec
    LEFT JOIN inventory_views.v_item_spec_resolved r ON r.spec_id = spec.id
    LEFT JOIN inventory."Item" i ON i.id = r.item_id
    LEFT JOIN inventory."Category" c ON c.id = i."categoryId"
),
seasonal AS (
    SELECT
        sc.spec_id,
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
    FROM spec_category sc
    LEFT JOIN category_annual ya ON ya.category_name = sc.category_name
    LEFT JOIN inventory_views.v_dashboard_seasonality cm
      ON cm.category_name = sc.category_name
     AND cm.month_of_year = EXTRACT(MONTH FROM CURRENT_DATE)::INT
)
SELECT
    spec.id AS spec_id,
    COALESCE(wc.daily_consumption_weighted, 0)::NUMERIC(14, 6) AS daily_consumption_weighted,
    COALESCE(wc.daily_consumption_simple, 0)::NUMERIC(14, 6) AS daily_consumption_simple,
    COALESCE(wc.is_reliable, FALSE) AS is_reliable,
    COALESCE(wc.movement_count, 0) AS movement_count,
    COALESCE(wc.effective_days, 0) AS effective_days,
    COALESCE(wc.total_consumption, 0)::BIGINT AS total_consumption,
    COALESCE(pd.demand_qty, 0)::INT AS demand_from_production,
    COALESCE(CEIL(ad.demand_qty), 0)::INT AS demand_from_assembly,
    COALESCE(se.seasonal_factor, 1::NUMERIC)::NUMERIC(8, 4) AS seasonal_factor,
    (
        COALESCE(wc.daily_consumption_weighted, 0::NUMERIC)
        * COALESCE(se.seasonal_factor, 1::NUMERIC)
    )::NUMERIC(14, 6) AS adjusted_daily_consumption
FROM inventory."ItemSpec" spec
LEFT JOIN weighted_calc wc ON wc.spec_id = spec.id
LEFT JOIN production_demand_by_spec pd ON pd.spec_id = spec.id
LEFT JOIN assembly_demand_by_spec ad ON ad.spec_id = spec.id
LEFT JOIN seasonal se ON se.spec_id = spec.id;
