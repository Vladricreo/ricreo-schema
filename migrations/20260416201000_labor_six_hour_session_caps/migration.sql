-- Solo viste labor (sync da product_cost_views.sql).
CREATE SCHEMA IF NOT EXISTS "inventory_views";

-- ============================================================================
-- 1. TEMPI DI LAVORO PER PRODOTTO
-- Sessioni tab (AssemblyOperation senza assemblyStageId = durata reale tra tab)
-- correlate alle righe stage (con assemblyStageId) con quantityProduced
-- il cui startedAt cade in [sessione inizio, sessione fine].
-- Tempo sessione ripartito proporzionalmente per tipo; cap:
--   LEAST(durata_sec, somma_qty_sessione * 21600) (~6 h/pezzo max per sessione; mitiga tablet lasciato giorni).
-- IQR (Tukey 1.5), min 10s/unità, cap 6h/unità; poi winsor P5–P95 per gruppo (code alta e bassa:
--   es. 30 min vs molti 3 min, e click troppo veloci sotto la coda tipica). recent_* NULL se campioni 90gg < 3.
-- ============================================================================

CREATE OR REPLACE VIEW inventory_views.v_product_labor_time_stats AS
WITH tab_sessions AS (
    SELECT
        op.id AS session_id,
        ao."productId" AS product_id,
        op."operatorId" AS operator_id,
        op."assemblyOrderId" AS assembly_order_id,
        op."startedAt" AS session_started_at,
        op."endedAt" AS session_ended_at,
        op."durationSeconds"::NUMERIC AS session_duration_sec
    FROM inventory."AssemblyOperation" op
    JOIN inventory."AssemblyOrder" ao ON op."assemblyOrderId" = ao.id
    WHERE op."assemblyStageId" IS NULL
      AND op."endedAt" IS NOT NULL
      AND op."durationSeconds" IS NOT NULL
      AND op."durationSeconds" > 0
),
session_qty_by_type AS (
    SELECT
        ts.session_id,
        ts.product_id,
        ts.operator_id,
        ts.session_started_at,
        ts.session_ended_at,
        ts.session_duration_sec,
        sq."type" AS operation_type,
        SUM(sq."quantityProduced")::NUMERIC AS qty_produced
    FROM tab_sessions ts
    INNER JOIN inventory."AssemblyOperation" sq
        ON sq."assemblyOrderId" = ts.assembly_order_id
       AND sq."assemblyStageId" IS NOT NULL
       AND sq."quantityProduced" > 0
       AND sq."startedAt" >= ts.session_started_at
       AND sq."startedAt" <= ts.session_ended_at
    GROUP BY
        ts.session_id,
        ts.product_id,
        ts.operator_id,
        ts.session_started_at,
        ts.session_ended_at,
        ts.session_duration_sec,
        sq."type"
),
session_total_qty AS (
    SELECT
        session_id,
        SUM(qty_produced)::NUMERIC AS total_qty
    FROM session_qty_by_type
    GROUP BY session_id
),
raw_ops AS (
    SELECT
        sbt.product_id,
        sbt.operation_type,
        (
            LEAST(sbt.session_duration_sec, st.total_qty * 21600)
            / NULLIF(st.total_qty, 0)
        ) AS seconds_per_unit,
        sbt.qty_produced AS quantity_produced,
        sbt.session_ended_at AS "endedAt"
    FROM session_qty_by_type sbt
    JOIN session_total_qty st ON st.session_id = sbt.session_id
    WHERE st.total_qty > 0
      AND sbt.qty_produced > 0
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
      AND r.seconds_per_unit <= 21600
      AND (
            (
              iq.iqr > 0
              AND r.seconds_per_unit >= (s.q1 - 1.5 * iq.iqr)
              AND r.seconds_per_unit <= (s.q3 + 1.5 * iq.iqr)
            )
            OR iq.iqr = 0
          )
),
winsor_bounds AS (
    SELECT
        product_id,
        operation_type,
        PERCENTILE_CONT(0.05) WITHIN GROUP (ORDER BY seconds_per_unit) AS p05,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY seconds_per_unit) AS p95
    FROM clean_ops
    GROUP BY product_id, operation_type
),
robust_ops AS (
    SELECT
        c.product_id,
        c.operation_type,
        LEAST(GREATEST(c.seconds_per_unit, w.p05), w.p95) AS seconds_per_unit,
        c.quantity_produced,
        c."endedAt"
    FROM clean_ops c
    JOIN winsor_bounds w
      ON w.product_id = c.product_id
     AND w.operation_type = c.operation_type
),
stage_avg_total AS (
    SELECT
        product_id,
        operation_type,
        AVG(seconds_per_unit) AS avg_stage_seconds
    FROM robust_ops
    GROUP BY product_id, operation_type
),
stage_monthly_detail AS (
    SELECT
        product_id,
        operation_type,
        DATE_TRUNC('month', "endedAt") AS op_month,
        AVG(seconds_per_unit) AS month_avg_spu
    FROM robust_ops
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
    FROM robust_ops
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
    FROM robust_ops c
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
      AND r.seconds_per_unit <= 21600
      AND (
            (
              iq.iqr > 0
              AND r.seconds_per_unit >= (s.q1 - 1.5 * iq.iqr)
              AND r.seconds_per_unit <= (s.q3 + 1.5 * iq.iqr)
            )
            OR iq.iqr = 0
          )
),
recent_winsor_bounds AS (
    SELECT
        product_id,
        operation_type,
        PERCENTILE_CONT(0.05) WITHIN GROUP (ORDER BY seconds_per_unit) AS p05,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY seconds_per_unit) AS p95
    FROM recent_clean_ops
    GROUP BY product_id, operation_type
),
recent_robust_ops AS (
    SELECT
        c.product_id,
        c.operation_type,
        LEAST(GREATEST(c.seconds_per_unit, w.p05), w.p95) AS seconds_per_unit,
        c.quantity_produced,
        c."endedAt"
    FROM recent_clean_ops c
    JOIN recent_winsor_bounds w
      ON w.product_id = c.product_id
     AND w.operation_type = c.operation_type
),
recent_stage_avg AS (
    SELECT
        product_id,
        operation_type,
        AVG(seconds_per_unit) AS avg_stage_seconds
    FROM recent_robust_ops
    GROUP BY product_id, operation_type
),
recent_stage_median AS (
    SELECT
        product_id,
        operation_type,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY seconds_per_unit) AS median_stage_seconds
    FROM recent_robust_ops
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
    FROM recent_robust_ops
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
    -- Recente (90gg): NULL se meno di 3 campioni nel periodo recente pulito
    CASE
        WHEN COALESCE(rsc.recent_sample_size, 0) >= 3 THEN CAST(rpt.recent_median_seconds_per_unit AS DECIMAL(12,2))
        ELSE NULL
    END AS recent_median_seconds_per_unit,
    CASE
        WHEN COALESCE(rsc.recent_sample_size, 0) >= 3 THEN CAST(rpt.recent_avg_seconds_per_unit AS DECIMAL(12,2))
        ELSE NULL
    END AS recent_avg_seconds_per_unit,
    CASE
        WHEN COALESCE(rsc.recent_sample_size, 0) >= 3 THEN CAST(rpt.recent_median_seconds_per_unit / 60.0 AS DECIMAL(10,2))
        ELSE NULL
    END AS recent_median_minutes_per_unit,
    CASE
        WHEN COALESCE(rsc.recent_sample_size, 0) >= 3 THEN CAST(rpt.recent_avg_seconds_per_unit / 60.0 AS DECIMAL(10,2))
        ELSE NULL
    END AS recent_avg_minutes_per_unit,
    COALESCE(rsc.recent_sample_size, 0) AS recent_sample_size
FROM product_totals pt
LEFT JOIN sample_counts sc ON sc.product_id = pt.product_id
LEFT JOIN recent_product_totals rpt ON rpt.product_id = pt.product_id
LEFT JOIN recent_sample_counts rsc ON rsc.product_id = pt.product_id;

-- ============================================================================
-- 1b. TEMPI DI LAVORO PER PRODOTTO E OPERATORE (breakdown audit / report)
-- Stessa logica sessione-tab + qty stage; IQR + min 10s + cap 6h; winsor P5–P95 per gruppo.
-- ============================================================================

CREATE OR REPLACE VIEW inventory_views.v_product_labor_by_operator AS
WITH tab_sessions AS (
    SELECT
        op.id AS session_id,
        ao."productId" AS product_id,
        op."operatorId" AS operator_id,
        op."assemblyOrderId" AS assembly_order_id,
        op."startedAt" AS session_started_at,
        op."endedAt" AS session_ended_at,
        op."durationSeconds"::NUMERIC AS session_duration_sec
    FROM inventory."AssemblyOperation" op
    JOIN inventory."AssemblyOrder" ao ON op."assemblyOrderId" = ao.id
    WHERE op."assemblyStageId" IS NULL
      AND op."endedAt" IS NOT NULL
      AND op."durationSeconds" IS NOT NULL
      AND op."durationSeconds" > 0
),
session_qty_by_type AS (
    SELECT
        ts.session_id,
        ts.product_id,
        ts.operator_id,
        ts.session_started_at,
        ts.session_ended_at,
        ts.session_duration_sec,
        sq."type" AS operation_type,
        SUM(sq."quantityProduced")::NUMERIC AS qty_produced
    FROM tab_sessions ts
    INNER JOIN inventory."AssemblyOperation" sq
        ON sq."assemblyOrderId" = ts.assembly_order_id
       AND sq."assemblyStageId" IS NOT NULL
       AND sq."quantityProduced" > 0
       AND sq."startedAt" >= ts.session_started_at
       AND sq."startedAt" <= ts.session_ended_at
    GROUP BY
        ts.session_id,
        ts.product_id,
        ts.operator_id,
        ts.session_started_at,
        ts.session_ended_at,
        ts.session_duration_sec,
        sq."type"
),
session_total_qty AS (
    SELECT
        session_id,
        SUM(qty_produced)::NUMERIC AS total_qty
    FROM session_qty_by_type
    GROUP BY session_id
),
raw_ops AS (
    SELECT
        sbt.product_id,
        sbt.operator_id,
        sbt.operation_type,
        (
            LEAST(sbt.session_duration_sec, st.total_qty * 21600)
            / NULLIF(st.total_qty, 0)
        ) AS seconds_per_unit,
        sbt.qty_produced AS quantity_produced,
        sbt.session_ended_at AS "endedAt"
    FROM session_qty_by_type sbt
    JOIN session_total_qty st ON st.session_id = sbt.session_id
    WHERE st.total_qty > 0
      AND sbt.qty_produced > 0
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
      AND r.seconds_per_unit <= 21600
      AND (
            (
              iq.iqr > 0
              AND r.seconds_per_unit >= (s.q1 - 1.5 * iq.iqr)
              AND r.seconds_per_unit <= (s.q3 + 1.5 * iq.iqr)
            )
            OR iq.iqr = 0
          )
),
winsor_bounds AS (
    SELECT
        product_id,
        operator_id,
        operation_type,
        PERCENTILE_CONT(0.05) WITHIN GROUP (ORDER BY seconds_per_unit) AS p05,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY seconds_per_unit) AS p95
    FROM clean_ops
    GROUP BY product_id, operator_id, operation_type
),
robust_ops AS (
    SELECT
        c.product_id,
        c.operator_id,
        c.operation_type,
        c.operator_name,
        LEAST(GREATEST(c.seconds_per_unit, w.p05), w.p95) AS seconds_per_unit,
        c.quantity_produced,
        c."endedAt"
    FROM clean_ops c
    JOIN winsor_bounds w
      ON w.product_id = c.product_id
     AND w.operator_id = c.operator_id
     AND w.operation_type = c.operation_type
),
per_stage AS (
    SELECT
        product_id,
        operator_id,
        MAX(operator_name) AS operator_name,
        operation_type,
        AVG(seconds_per_unit) AS avg_spu,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY seconds_per_unit) AS median_spu,
        SUM(quantity_produced)::BIGINT AS units_in_type,
        COUNT(*)::INT AS ops_in_type,
        MAX("endedAt") AS last_ended_in_type
    FROM robust_ops
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
