-- ============================================================================
-- PRODUCT COST VIEWS
-- Calcolo costi prodotto centralizzato lato DB.
-- Separazione: costo materie prime vs costo operativo (lavoro).
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS "inventory_views";

-- ============================================================================
-- 1. TEMPI DI LAVORO PER PRODOTTO
-- Sorgente: AssemblyOperation + AssemblyOrder
-- Calcola mediana, media totale e media mensile dei secondi/unità.
-- Media mensile: media delle medie dei mesi in cui ci sono stati assemblaggi.
-- Filtra outlier con IQR (Tukey 1.5), min 10s/unità, cap 2h per operazione.
-- Ultimi 90 giorni: stessa logica; se campioni recenti < 5, colonne recent_* NULL.
-- ============================================================================

CREATE OR REPLACE VIEW inventory_views.v_product_labor_time_stats AS
WITH raw_ops AS (
    SELECT
        ao."productId" AS product_id,
        op."type" AS operation_type,
        op."durationSeconds",
        op."quantityProduced",
        op."endedAt",
        (op."durationSeconds"::NUMERIC / NULLIF(op."quantityProduced", 0)) AS seconds_per_unit
    FROM inventory."AssemblyOperation" op
    JOIN inventory."AssemblyOrder" ao ON op."assemblyOrderId" = ao.id
    WHERE op."durationSeconds" IS NOT NULL
      AND op."quantityProduced" > 0
      AND op."endedAt" IS NOT NULL
),
-- Limiti IQR per (prodotto, tipo) su tutti i dati (prima fence, poi min/cap)
iqr_stats AS (
    SELECT
        product_id,
        operation_type,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY seconds_per_unit) AS q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY seconds_per_unit) AS q3
    FROM raw_ops
    GROUP BY product_id, operation_type
),
clean_ops AS (
    SELECT r.*
    FROM raw_ops r
    JOIN iqr_stats s ON r.product_id = s.product_id AND r.operation_type = s.operation_type
    CROSS JOIN LATERAL (
        SELECT GREATEST(s.q3 - s.q1, 0::NUMERIC) AS iqr
    ) iq
    WHERE r.seconds_per_unit >= 10
      AND r.seconds_per_unit <= 7200
      AND (
            iq.iqr > 0
            AND r.seconds_per_unit >= (s.q1 - 1.5 * iq.iqr)
            AND r.seconds_per_unit <= (s.q3 + 1.5 * iq.iqr)
          )
       OR (
            iq.iqr = 0
          )
),
stage_avg_total AS (
    SELECT
        product_id,
        operation_type,
        AVG(seconds_per_unit) AS avg_stage_seconds
    FROM clean_ops
    GROUP BY product_id, operation_type
),
stage_monthly_detail AS (
    SELECT
        product_id,
        operation_type,
        DATE_TRUNC('month', "endedAt") AS op_month,
        AVG(seconds_per_unit) AS month_avg_spu
    FROM clean_ops
    GROUP BY product_id, operation_type, DATE_TRUNC('month', "endedAt")
),
stage_avg_monthly AS (
    SELECT
        product_id,
        operation_type,
        AVG(month_avg_spu) AS avg_stage_seconds_monthly,
        COUNT(DISTINCT op_month)::INT AS months_with_data
    FROM stage_monthly_detail
    GROUP BY product_id, operation_type
),
stage_median AS (
    SELECT
        product_id,
        operation_type,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY seconds_per_unit) AS median_stage_seconds
    FROM clean_ops
    GROUP BY product_id, operation_type
),
product_totals AS (
    SELECT
        t.product_id,
        COALESCE(SUM(t.avg_stage_seconds), 0)::NUMERIC AS avg_seconds_per_unit_total,
        COALESCE(SUM(m.median_stage_seconds), 0)::NUMERIC AS median_seconds_per_unit,
        COALESCE(SUM(mo.avg_stage_seconds_monthly), SUM(t.avg_stage_seconds), 0)::NUMERIC AS avg_seconds_per_unit_monthly
    FROM stage_avg_total t
    LEFT JOIN stage_median m ON m.product_id = t.product_id AND m.operation_type = t.operation_type
    LEFT JOIN stage_avg_monthly mo ON mo.product_id = t.product_id AND mo.operation_type = t.operation_type
    GROUP BY t.product_id
),
sample_counts AS (
    SELECT
        c.product_id,
        COUNT(*)::INT AS sample_size_total,
        COALESCE(MAX(mo.months_with_data), 0) AS months_with_data
    FROM clean_ops c
    LEFT JOIN (
        SELECT product_id, COUNT(DISTINCT op_month)::INT AS months_with_data
        FROM stage_monthly_detail
        GROUP BY product_id
    ) mo ON mo.product_id = c.product_id
    GROUP BY c.product_id
),
-- --- Ultimi 90 giorni (stessa logica IQR sul sottoinsieme recente) ---
recent_raw AS (
    SELECT *
    FROM raw_ops
    WHERE "endedAt" >= NOW() - INTERVAL '90 days'
),
recent_iqr_stats AS (
    SELECT
        product_id,
        operation_type,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY seconds_per_unit) AS q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY seconds_per_unit) AS q3
    FROM recent_raw
    GROUP BY product_id, operation_type
),
recent_clean_ops AS (
    SELECT r.*
    FROM recent_raw r
    JOIN recent_iqr_stats s ON r.product_id = s.product_id AND r.operation_type = s.operation_type
    CROSS JOIN LATERAL (
        SELECT GREATEST(s.q3 - s.q1, 0::NUMERIC) AS iqr
    ) iq
    WHERE r.seconds_per_unit >= 10
      AND r.seconds_per_unit <= 7200
      AND (
            iq.iqr > 0
            AND r.seconds_per_unit >= (s.q1 - 1.5 * iq.iqr)
            AND r.seconds_per_unit <= (s.q3 + 1.5 * iq.iqr)
          )
       OR (
            iq.iqr = 0
          )
),
recent_stage_avg AS (
    SELECT
        product_id,
        operation_type,
        AVG(seconds_per_unit) AS avg_stage_seconds
    FROM recent_clean_ops
    GROUP BY product_id, operation_type
),
recent_stage_median AS (
    SELECT
        product_id,
        operation_type,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY seconds_per_unit) AS median_stage_seconds
    FROM recent_clean_ops
    GROUP BY product_id, operation_type
),
recent_product_totals AS (
    SELECT
        t.product_id,
        COALESCE(SUM(t.avg_stage_seconds), 0)::NUMERIC AS recent_avg_seconds_per_unit,
        COALESCE(SUM(m.median_stage_seconds), 0)::NUMERIC AS recent_median_seconds_per_unit
    FROM recent_stage_avg t
    LEFT JOIN recent_stage_median m ON m.product_id = t.product_id AND m.operation_type = t.operation_type
    GROUP BY t.product_id
),
recent_sample_counts AS (
    SELECT
        product_id,
        COUNT(*)::INT AS recent_sample_size
    FROM recent_clean_ops
    GROUP BY product_id
)
SELECT
    pt.product_id,
    CAST(pt.median_seconds_per_unit AS DECIMAL(12,2)) AS median_seconds_per_unit,
    CAST(pt.avg_seconds_per_unit_total AS DECIMAL(12,2)) AS avg_seconds_per_unit_total,
    CAST(pt.avg_seconds_per_unit_monthly AS DECIMAL(12,2)) AS avg_seconds_per_unit_monthly,
    CAST(pt.median_seconds_per_unit / 60.0 AS DECIMAL(10,2)) AS median_minutes_per_unit,
    CAST(pt.avg_seconds_per_unit_total / 60.0 AS DECIMAL(10,2)) AS avg_minutes_per_unit_total,
    CAST(pt.avg_seconds_per_unit_monthly / 60.0 AS DECIMAL(10,2)) AS avg_minutes_per_unit_monthly,
    COALESCE(sc.sample_size_total, 0) AS sample_size_total,
    COALESCE(sc.months_with_data, 0) AS months_with_data,
    -- Recente (90gg): NULL se meno di 5 campioni nel periodo recente pulito
    CASE
        WHEN COALESCE(rsc.recent_sample_size, 0) >= 5 THEN CAST(rpt.recent_median_seconds_per_unit AS DECIMAL(12,2))
        ELSE NULL
    END AS recent_median_seconds_per_unit,
    CASE
        WHEN COALESCE(rsc.recent_sample_size, 0) >= 5 THEN CAST(rpt.recent_avg_seconds_per_unit AS DECIMAL(12,2))
        ELSE NULL
    END AS recent_avg_seconds_per_unit,
    CASE
        WHEN COALESCE(rsc.recent_sample_size, 0) >= 5 THEN CAST(rpt.recent_median_seconds_per_unit / 60.0 AS DECIMAL(10,2))
        ELSE NULL
    END AS recent_median_minutes_per_unit,
    CASE
        WHEN COALESCE(rsc.recent_sample_size, 0) >= 5 THEN CAST(rpt.recent_avg_seconds_per_unit / 60.0 AS DECIMAL(10,2))
        ELSE NULL
    END AS recent_avg_minutes_per_unit,
    COALESCE(rsc.recent_sample_size, 0) AS recent_sample_size
FROM product_totals pt
LEFT JOIN sample_counts sc ON sc.product_id = pt.product_id
LEFT JOIN recent_product_totals rpt ON rpt.product_id = pt.product_id
LEFT JOIN recent_sample_counts rsc ON rsc.product_id = pt.product_id;

-- ============================================================================
-- 1b. TEMPI DI LAVORO PER PRODOTTO E OPERATORE (breakdown audit / report)
-- Stessi filtri IQR + min 10s + cap 2h; aggregato su tutti i dati disponibili.
-- ============================================================================

CREATE OR REPLACE VIEW inventory_views.v_product_labor_by_operator AS
WITH raw_ops AS (
    SELECT
        ao."productId" AS product_id,
        op."operatorId" AS operator_id,
        op."type" AS operation_type,
        op."durationSeconds",
        op."quantityProduced",
        op."endedAt",
        (op."durationSeconds"::NUMERIC / NULLIF(op."quantityProduced", 0)) AS seconds_per_unit
    FROM inventory."AssemblyOperation" op
    JOIN inventory."AssemblyOrder" ao ON op."assemblyOrderId" = ao.id
    WHERE op."durationSeconds" IS NOT NULL
      AND op."quantityProduced" > 0
      AND op."endedAt" IS NOT NULL
),
iqr_stats AS (
    SELECT
        product_id,
        operator_id,
        operation_type,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY seconds_per_unit) AS q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY seconds_per_unit) AS q3
    FROM raw_ops
    GROUP BY product_id, operator_id, operation_type
),
clean_ops AS (
    SELECT r.*, u.name AS operator_name
    FROM raw_ops r
    JOIN iqr_stats s
      ON r.product_id = s.product_id
     AND r.operator_id = s.operator_id
     AND r.operation_type = s.operation_type
    JOIN public."User" u ON u.id = r.operator_id
    CROSS JOIN LATERAL (
        SELECT GREATEST(s.q3 - s.q1, 0::NUMERIC) AS iqr
    ) iq
    WHERE r.seconds_per_unit >= 10
      AND r.seconds_per_unit <= 7200
      AND (
            iq.iqr > 0
            AND r.seconds_per_unit >= (s.q1 - 1.5 * iq.iqr)
            AND r.seconds_per_unit <= (s.q3 + 1.5 * iq.iqr)
          )
       OR (
            iq.iqr = 0
          )
),
per_stage AS (
    SELECT
        product_id,
        operator_id,
        MAX(operator_name) AS operator_name,
        operation_type,
        AVG(seconds_per_unit) AS avg_spu,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY seconds_per_unit) AS median_spu,
        SUM("quantityProduced")::BIGINT AS units_in_type,
        COUNT(*)::INT AS ops_in_type,
        MAX("endedAt") AS last_ended_in_type
    FROM clean_ops
    GROUP BY product_id, operator_id, operation_type
)
SELECT
    product_id,
    operator_id,
    MAX(operator_name) AS operator_name,
    CAST(COALESCE(SUM(median_spu), 0) AS DECIMAL(12,2)) AS median_seconds_per_unit,
    CAST(COALESCE(SUM(avg_spu), 0) AS DECIMAL(12,2)) AS avg_seconds_per_unit,
    CAST(COALESCE(SUM(median_spu), 0) / 60.0 AS DECIMAL(10,2)) AS median_minutes_per_unit,
    CAST(COALESCE(SUM(avg_spu), 0) / 60.0 AS DECIMAL(10,2)) AS avg_minutes_per_unit,
    COALESCE(SUM(units_in_type), 0)::BIGINT AS total_units_produced,
    COALESCE(SUM(ops_in_type), 0)::INT AS total_operations,
    MAX(last_ended_in_type) AS last_assembly_at
FROM per_stage
GROUP BY product_id, operator_id;

-- ============================================================================
-- 2. BREAKDOWN COSTO MATERIE PRIME PER PRODOTTO (unitario, per 1 prodotto)
-- Include: materiali BOM delle parti MAKE, costo parti BUY,
--          componenti, packaging, utility (priority=0, tutti gli SKU).
-- Non include: costo lavoro (quello è operativo).
-- ============================================================================

CREATE OR REPLACE VIEW inventory_views.v_product_cost_breakdown AS
WITH material_cost AS (
    SELECT
        pp."productId" AS product_id,
        SUM(
            pp."quantityNeeded"::NUMERIC
            * mb."usedWeight"::NUMERIC
            * CASE
                WHEN (COALESCE(i.weight, sw.weight, 0)::NUMERIC * 1000) > 0
                  THEN (i.price::NUMERIC / (COALESCE(i.weight, sw.weight, 0)::NUMERIC * 1000))
                ELSE 0
              END
        ) AS materials_cost
    FROM inventory."ProductPart" pp
    JOIN inventory."ProductPartMaterial" mb
      ON mb."productPartId" = pp.id AND mb.priority = 0
    JOIN inventory_views.v_item_spec_resolved ri
      ON ri.spec_id = mb."materialSpecId"
    JOIN inventory."Item" i ON i.id = ri.item_id
    LEFT JOIN inventory."StandardWeight" sw ON sw.id = i."standardWeightId"
    WHERE pp."sourceType" = 'MAKE'
    GROUP BY pp."productId"
),
buy_parts_cost AS (
    SELECT
        pp."productId" AS product_id,
        SUM(COALESCE(pp.price, 0)::NUMERIC * pp."quantityNeeded"::NUMERIC) AS buy_parts_cost
    FROM inventory."ProductPart" pp
    WHERE pp."sourceType" = 'BUY'
    GROUP BY pp."productId"
),
component_cost AS (
    SELECT
        c."productId" AS product_id,
        SUM(COALESCE(i.price, 0)::NUMERIC * c.quantity::NUMERIC) AS components_cost
    FROM inventory."ProductToComponent" c
    JOIN inventory_views.v_item_spec_resolved ri ON ri.spec_id = c."itemSpecId"
    JOIN inventory."Item" i ON i.id = ri.item_id
    WHERE c.priority = 0
    GROUP BY c."productId"
),
packaging_cost AS (
    SELECT
        p."productId" AS product_id,
        SUM(COALESCE(i.price, 0)::NUMERIC * p.quantity::NUMERIC) AS packaging_cost
    FROM inventory."ProductToPackage" p
    JOIN inventory_views.v_item_spec_resolved ri ON ri.spec_id = p."itemSpecId"
    JOIN inventory."Item" i ON i.id = ri.item_id
    WHERE p.priority = 0
    GROUP BY p."productId"
),
utility_cost AS (
    SELECT
        u."productId" AS product_id,
        SUM(COALESCE(i.price, 0)::NUMERIC * u.quantity::NUMERIC) AS utilities_cost
    FROM inventory."ProductToUtility" u
    JOIN inventory_views.v_item_spec_resolved ri ON ri.spec_id = u."itemSpecId"
    JOIN inventory."Item" i ON i.id = ri.item_id
    WHERE u.priority = 0
    GROUP BY u."productId"
)
SELECT
    pr.id AS product_id,
    COALESCE(mc.materials_cost, 0)::DECIMAL(12,4) AS materials_cost,
    COALESCE(bp.buy_parts_cost, 0)::DECIMAL(12,4) AS buy_parts_cost,
    COALESCE(cc.components_cost, 0)::DECIMAL(12,4) AS components_cost,
    COALESCE(pc.packaging_cost, 0)::DECIMAL(12,4) AS packaging_cost,
    COALESCE(uc.utilities_cost, 0)::DECIMAL(12,4) AS utilities_cost,
    (
        COALESCE(mc.materials_cost, 0)
      + COALESCE(bp.buy_parts_cost, 0)
      + COALESCE(cc.components_cost, 0)
      + COALESCE(pc.packaging_cost, 0)
      + COALESCE(uc.utilities_cost, 0)
    )::DECIMAL(12,4) AS raw_material_cost
FROM inventory."Product" pr
LEFT JOIN material_cost mc ON mc.product_id = pr.id
LEFT JOIN buy_parts_cost bp ON bp.product_id = pr.id
LEFT JOIN component_cost cc ON cc.product_id = pr.id
LEFT JOIN packaging_cost pc ON pc.product_id = pr.id
LEFT JOIN utility_cost uc ON uc.product_id = pr.id;

-- ============================================================================
-- 3. PRICING SUMMARY PER PRODOTTO
-- Join: Product + v_product_cost_breakdown + v_product_labor_time_stats + Settings
-- Costo operativo: COALESCE(mediana 90gg, mediana storica).
-- ============================================================================

CREATE OR REPLACE VIEW inventory_views.v_product_pricing_summary AS
WITH settings_labor AS (
    SELECT
        CASE
            WHEN value::text ~ '^[0-9.]+$' THEN (value::text)::NUMERIC
            WHEN jsonb_typeof(value::jsonb) = 'number' THEN (value::text)::NUMERIC
            WHEN (value::jsonb) ? 'value' THEN (value::jsonb->>'value')::NUMERIC
            ELSE 0
        END AS hourly_rate
    FROM inventory."Settings"
    WHERE name = 'LABOR_COST'
    LIMIT 1
),
settings_margin AS (
    SELECT
        CASE
            WHEN value::text ~ '^[0-9.]+$' THEN (value::text)::NUMERIC
            WHEN jsonb_typeof(value::jsonb) = 'number' THEN (value::text)::NUMERIC
            WHEN (value::jsonb) ? 'value' THEN (value::jsonb->>'value')::NUMERIC
            ELSE 0.3
        END AS profit_margin
    FROM inventory."Settings"
    WHERE name = 'PROFIT_MARGIN'
    LIMIT 1
)
SELECT
    p.id AS product_id,
    p.name AS product_name,

    -- Costo materie prime
    cb.materials_cost,
    cb.buy_parts_cost,
    cb.components_cost,
    cb.packaging_cost,
    cb.utilities_cost,
    cb.raw_material_cost,

    -- Metriche tempi lavoro (storico)
    COALESCE(lt.median_seconds_per_unit, 0)::DECIMAL(12,2) AS median_seconds_per_unit,
    COALESCE(lt.avg_seconds_per_unit_total, 0)::DECIMAL(12,2) AS avg_seconds_per_unit_total,
    COALESCE(lt.avg_seconds_per_unit_monthly, 0)::DECIMAL(12,2) AS avg_seconds_per_unit_monthly,
    COALESCE(lt.median_minutes_per_unit, 0)::DECIMAL(10,2) AS median_minutes_per_unit,
    COALESCE(lt.avg_minutes_per_unit_total, 0)::DECIMAL(10,2) AS avg_minutes_per_unit_total,
    COALESCE(lt.avg_minutes_per_unit_monthly, 0)::DECIMAL(10,2) AS avg_minutes_per_unit_monthly,
    COALESCE(lt.sample_size_total, 0) AS sample_size_total,
    COALESCE(lt.months_with_data, 0) AS months_with_data,

    -- Costo operativo (lavoro): mediana recente se campioni sufficienti, altrimenti storica
    CAST(
        (COALESCE(lt.recent_median_seconds_per_unit, lt.median_seconds_per_unit, 0) / 3600.0)
        * COALESCE((SELECT hourly_rate FROM settings_labor), 0)
    AS DECIMAL(12,4)) AS operational_cost,

    -- Stima costo spedizione (manuale, dal prodotto)
    COALESCE(p."shippingCost", 0)::DECIMAL(12,2) AS shipping_cost,

    -- Costo totale unitario (produzione + spedizione)
    CAST(
        cb.raw_material_cost
        + (COALESCE(lt.recent_median_seconds_per_unit, lt.median_seconds_per_unit, 0) / 3600.0)
          * COALESCE((SELECT hourly_rate FROM settings_labor), 0)
        + COALESCE(p."shippingCost", 0)
    AS DECIMAL(12,4)) AS total_cost,

    -- Prezzo suggerito base (costo totale * (1 + margine)).
    CAST(
        (
            cb.raw_material_cost
            + (COALESCE(lt.recent_median_seconds_per_unit, lt.median_seconds_per_unit, 0) / 3600.0)
              * COALESCE((SELECT hourly_rate FROM settings_labor), 0)
            + COALESCE(p."shippingCost", 0)
        ) * (1 + COALESCE((SELECT profit_margin FROM settings_margin), 0.3))
    AS DECIMAL(12,2)) AS suggested_price,

    -- Prezzo manuale / effettivo
    p."sellingPrice",
    COALESCE(p."sellingPrice",
        CAST(
            (
                cb.raw_material_cost
                + (COALESCE(lt.recent_median_seconds_per_unit, lt.median_seconds_per_unit, 0) / 3600.0)
                  * COALESCE((SELECT hourly_rate FROM settings_labor), 0)
                + COALESCE(p."shippingCost", 0)
            ) * (1 + COALESCE((SELECT profit_margin FROM settings_margin), 0.3))
        AS DECIMAL(12,2))
    ) AS effective_selling_price,

    -- Recente (90gg), può essere NULL
    lt.recent_median_seconds_per_unit,
    lt.recent_avg_seconds_per_unit,
    lt.recent_median_minutes_per_unit,
    lt.recent_avg_minutes_per_unit,
    COALESCE(lt.recent_sample_size, 0) AS recent_sample_size,

    -- Secondi/unità usati per il costo operativo (recente se disponibile)
    COALESCE(lt.recent_median_seconds_per_unit, lt.median_seconds_per_unit, 0)::DECIMAL(12,2) AS effective_labor_seconds_per_unit,

    -- Manodopera da mediana storica (confronto UI)
    CAST(
        (COALESCE(lt.median_seconds_per_unit, 0) / 3600.0)
        * COALESCE((SELECT hourly_rate FROM settings_labor), 0)
    AS DECIMAL(12,4)) AS historical_operational_cost,

    -- Costo operativo da solo dato recente (NULL se recente non valido)
    CASE
        WHEN lt.recent_median_seconds_per_unit IS NOT NULL THEN
            CAST(
                (lt.recent_median_seconds_per_unit / 3600.0)
                * COALESCE((SELECT hourly_rate FROM settings_labor), 0)
            AS DECIMAL(12,4))
        ELSE NULL
    END AS recent_operational_cost,

    -- Costo produzione (materie + manodopera effettiva), senza spedizione
    CAST(
        cb.raw_material_cost
        + (COALESCE(lt.recent_median_seconds_per_unit, lt.median_seconds_per_unit, 0) / 3600.0)
          * COALESCE((SELECT hourly_rate FROM settings_labor), 0)
    AS DECIMAL(12,4)) AS production_cost

FROM inventory."Product" p
JOIN inventory_views.v_product_cost_breakdown cb ON cb.product_id = p.id
LEFT JOIN inventory_views.v_product_labor_time_stats lt ON lt.product_id = p.id;
