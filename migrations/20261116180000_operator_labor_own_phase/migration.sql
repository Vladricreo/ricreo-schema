-- S-303 (16/11/2026): i tempi di un operatore sono solo i suoi, per fase.
--
-- Prima `v_product_labor_by_operator` prendeva da `v_assembly_labor_samples`
-- il tempo/pezzo dell'ORDINE (secondi di tutti gli operatori ÷ pezzi
-- dell'ordine) e lo attribuiva a ogni operatore che aveva toccato l'ordine;
-- anche i pezzi erano quelli dell'ordine intero.
--
-- Regola nuova (la stessa di «I miei tempi», `client/src/lib/user-dashboard.ts`),
-- decisa con l'utente il 16/11: per operatore, ordine e fase,
--   tempo delle sue sessioni (righe senza `assemblyStageId`, non escluse,
--   durata limitata a 12 h) ÷ pezzi registrati da lui nella stessa fase e
--   ordine (righe con `assemblyStageId`, limitati al lotto dell'ordine).
-- Le fasi non si sommano fra loro come pezzi. Le sessioni senza pezzi suoi
-- (ha aiutato, i pezzi li ha registrati un collega) restano nelle ore ma non
-- nel tempo/pezzo: qui hanno quantity_produced = 0 e seconds_per_unit NULL.
--
-- NON cambia `v_assembly_labor_samples` né `v_product_labor_time_stats`
-- (costo/pezzo del prodotto, usato da `v_product_pricing_summary`).

-- 1) Campioni per operatore, ordine e fase (solo ordini completati).
CREATE OR REPLACE VIEW inventory_views.v_operator_labor_samples AS
WITH settings_labor AS (
  SELECT
    CASE
      WHEN "Settings".value::text ~ '^[0-9.]+$'::text THEN "Settings".value::text::numeric
      WHEN jsonb_typeof("Settings".value) = 'number'::text THEN "Settings".value::text::numeric
      WHEN "Settings".value ? 'value'::text THEN ("Settings".value ->> 'value'::text)::numeric
      ELSE 0::numeric
    END AS hourly_rate
  FROM inventory."Settings"
  WHERE "Settings".name = 'LABOR_COST'::inventory."SettingsName"
  LIMIT 1
), operator_hourly_cost AS (
  SELECT
    ws."userId" AS operator_id,
    sum(ws.cost::numeric * (ws."endMinute" - ws."startMinute")::numeric)
      / NULLIF(sum((ws."endMinute" - ws."startMinute")::numeric), 0::numeric) AS avg_hourly_rate
  FROM "WorkShift" ws
  WHERE ws."isActive" = true AND ws.cost IS NOT NULL AND ws."endMinute" > ws."startMinute"
  GROUP BY ws."userId"
), completed_orders AS (
  SELECT
    ao.id AS assembly_order_id,
    ao."productId" AS product_id,
    ao."quantityToAssemble" AS quantity_to_assemble,
    ao."finishedAt" AS finished_at
  FROM inventory."AssemblyOrder" ao
  WHERE ao.status = 'ASSEMBLY_COMPLETED'::inventory."AssemblyStatus"
    AND ao."quantityAssembled" > 0
), sessions AS (
  SELECT
    co.product_id,
    op."assemblyOrderId" AS assembly_order_id,
    op."operatorId" AS operator_id,
    op.type AS operation_type,
    op."endedAt" AS session_ended_at,
    LEAST(op."durationSeconds"::numeric, 43200::numeric) AS session_duration_sec,
    COALESCE(
      matched_shift.cost::numeric,
      ohc.avg_hourly_rate,
      (SELECT settings_labor.hourly_rate FROM settings_labor),
      0::numeric
    ) AS hourly_rate
  FROM inventory."AssemblyOperation" op
  JOIN completed_orders co ON co.assembly_order_id = op."assemblyOrderId"
  LEFT JOIN LATERAL (
    SELECT ws.cost
    FROM "WorkShift" ws
    WHERE ws."userId" = op."operatorId"
      AND ws."isActive" = true
      AND ws.cost IS NOT NULL
      AND ws."dayOfWeek" = EXTRACT(dow FROM op."startedAt")::integer
      AND (EXTRACT(hour FROM op."startedAt")::integer * 60 + EXTRACT(minute FROM op."startedAt")::integer) >= ws."startMinute"
      AND (EXTRACT(hour FROM op."startedAt")::integer * 60 + EXTRACT(minute FROM op."startedAt")::integer) < ws."endMinute"
    ORDER BY ws."startMinute" DESC
    LIMIT 1
  ) matched_shift ON true
  LEFT JOIN operator_hourly_cost ohc ON ohc.operator_id = op."operatorId"
  WHERE op."assemblyStageId" IS NULL
    AND op."endedAt" IS NOT NULL
    AND op."durationSeconds" IS NOT NULL
    AND op."durationSeconds" > 0
    AND op."excludedFromLaborStats" = false
), session_totals AS (
  SELECT
    product_id,
    assembly_order_id,
    operator_id,
    operation_type,
    sum(session_duration_sec) AS session_seconds,
    sum(session_duration_sec * hourly_rate) AS session_cost_seconds,
    max(session_ended_at) AS last_session_ended_at
  FROM sessions
  GROUP BY product_id, assembly_order_id, operator_id, operation_type
), own_pieces AS (
  SELECT
    op."assemblyOrderId" AS assembly_order_id,
    op."operatorId" AS operator_id,
    op.type AS operation_type,
    sum(op."quantityProduced")::numeric AS pieces
  FROM inventory."AssemblyOperation" op
  JOIN completed_orders co ON co.assembly_order_id = op."assemblyOrderId"
  WHERE op."assemblyStageId" IS NOT NULL
    AND op."quantityProduced" > 0
  GROUP BY op."assemblyOrderId", op."operatorId", op.type
), joined AS (
  SELECT
    st.product_id,
    st.assembly_order_id,
    st.operator_id,
    st.operation_type,
    st.session_seconds,
    st.session_cost_seconds,
    -- Pezzi suoi in questa fase, mai oltre il lotto (vecchi doppi conteggi).
    CASE
      WHEN co.quantity_to_assemble > 0
        THEN LEAST(COALESCE(p.pieces, 0), co.quantity_to_assemble::numeric)
      ELSE COALESCE(p.pieces, 0)
    END AS quantity_produced,
    COALESCE(co.finished_at, st.last_session_ended_at) AS "endedAt"
  FROM session_totals st
  JOIN completed_orders co ON co.assembly_order_id = st.assembly_order_id
  LEFT JOIN own_pieces p
    ON p.assembly_order_id = st.assembly_order_id
   AND p.operator_id = st.operator_id
   AND p.operation_type = st.operation_type
  WHERE st.session_seconds > 0
)
SELECT
  product_id,
  assembly_order_id,
  operator_id,
  operation_type,
  quantity_produced,
  session_seconds AS total_seconds,
  CASE WHEN quantity_produced > 0
    THEN session_seconds / quantity_produced
  END AS seconds_per_unit,
  CASE WHEN quantity_produced > 0
    THEN session_cost_seconds / 3600.0 / quantity_produced
  END AS labor_cost_per_unit,
  "endedAt"
FROM joined;

COMMENT ON VIEW inventory_views.v_operator_labor_samples IS
  'S-303: per operatore, ordine completato e fase: sue sessioni (cap 12 h, non escluse) / suoi pezzi della stessa fase. quantity_produced = 0 e seconds_per_unit NULL = ore di aiuto senza pezzi suoi.';

-- 2) Mediana per prodotto e fase fra tutti gli operatori (termine di confronto).
CREATE OR REPLACE VIEW inventory_views.v_product_phase_labor_stats AS
SELECT
  product_id,
  operation_type,
  (percentile_cont(0.5) WITHIN GROUP (ORDER BY seconds_per_unit::double precision))::numeric(12,2) AS median_seconds_per_unit,
  (percentile_cont(0.5) WITHIN GROUP (ORDER BY seconds_per_unit::double precision) / 60.0)::numeric(10,2) AS median_minutes_per_unit,
  (percentile_cont(0.5) WITHIN GROUP (ORDER BY labor_cost_per_unit::double precision))::numeric(12,4) AS median_labor_cost_per_unit,
  count(*)::integer AS sample_size,
  count(DISTINCT operator_id)::integer AS operator_count
FROM inventory_views.v_operator_labor_samples
WHERE seconds_per_unit >= 10 AND seconds_per_unit <= 21600
GROUP BY product_id, operation_type;

COMMENT ON VIEW inventory_views.v_product_phase_labor_stats IS
  'S-303: mediana del tempo/pezzo per prodotto e fase su tutti i campioni operatore (10 s - 6 h).';

-- 3) Per prodotto, operatore e fase: cambia la chiave (c'è la fase), quindi
--    DROP + CREATE. Nessuna vista dipende da questa.
DROP VIEW IF EXISTS inventory_views.v_product_labor_by_operator;

CREATE VIEW inventory_views.v_product_labor_by_operator AS
WITH bounded_ops AS (
  SELECT *
  FROM inventory_views.v_operator_labor_samples
  WHERE seconds_per_unit >= 10 AND seconds_per_unit <= 21600
), iqr_stats AS (
  SELECT
    product_id,
    operator_id,
    operation_type,
    percentile_cont(0.25) WITHIN GROUP (ORDER BY seconds_per_unit::double precision) AS q1,
    percentile_cont(0.75) WITHIN GROUP (ORDER BY seconds_per_unit::double precision) AS q3
  FROM bounded_ops
  GROUP BY product_id, operator_id, operation_type
), clean_ops AS (
  SELECT r.*, u.name AS operator_name
  FROM bounded_ops r
  JOIN iqr_stats s
    ON s.product_id = r.product_id
   AND s.operator_id = r.operator_id
   AND s.operation_type = r.operation_type
  JOIN "User" u ON u.id = r.operator_id
  CROSS JOIN LATERAL (SELECT GREATEST(s.q3 - s.q1, 0::double precision) AS iqr) iq
  WHERE iq.iqr = 0
     OR (r.seconds_per_unit::double precision >= s.q1 - 1.5 * iq.iqr
         AND r.seconds_per_unit::double precision <= s.q3 + 1.5 * iq.iqr)
), winsor_bounds AS (
  SELECT
    product_id,
    operator_id,
    operation_type,
    percentile_cont(0.05) WITHIN GROUP (ORDER BY seconds_per_unit::double precision) AS p05,
    percentile_cont(0.95) WITHIN GROUP (ORDER BY seconds_per_unit::double precision) AS p95
  FROM clean_ops
  GROUP BY product_id, operator_id, operation_type
), robust_ops AS (
  SELECT
    c.product_id,
    c.operator_id,
    c.operation_type,
    c.operator_name,
    LEAST(GREATEST(c.seconds_per_unit::double precision, w.p05), w.p95) AS seconds_per_unit,
    c.labor_cost_per_unit,
    c.quantity_produced,
    c.total_seconds,
    c."endedAt"
  FROM clean_ops c
  JOIN winsor_bounds w
    ON w.product_id = c.product_id
   AND w.operator_id = c.operator_id
   AND w.operation_type = c.operation_type
)
SELECT
  r.product_id,
  r.operator_id,
  max(r.operator_name) AS operator_name,
  (percentile_cont(0.5) WITHIN GROUP (ORDER BY r.seconds_per_unit))::numeric(12,2) AS median_seconds_per_unit,
  avg(r.seconds_per_unit)::numeric(12,2) AS avg_seconds_per_unit,
  (percentile_cont(0.5) WITHIN GROUP (ORDER BY r.seconds_per_unit) / 60.0)::numeric(10,2) AS median_minutes_per_unit,
  (avg(r.seconds_per_unit) / 60.0)::numeric(10,2) AS avg_minutes_per_unit,
  COALESCE(sum(r.quantity_produced), 0)::bigint AS total_units_produced,
  count(*)::integer AS total_operations,
  max(r."endedAt") AS last_assembly_at,
  (percentile_cont(0.5) WITHIN GROUP (ORDER BY r.labor_cost_per_unit::double precision))::numeric(12,4) AS median_labor_cost_per_unit,
  avg(r.labor_cost_per_unit)::numeric(12,4) AS avg_labor_cost_per_unit,
  r.operation_type,
  sum(r.total_seconds)::numeric(14,0) AS total_seconds,
  max(ph.median_minutes_per_unit) AS phase_median_minutes_per_unit,
  max(ph.median_labor_cost_per_unit) AS phase_median_labor_cost_per_unit,
  max(ph.sample_size) AS phase_sample_size
FROM robust_ops r
LEFT JOIN inventory_views.v_product_phase_labor_stats ph
  ON ph.product_id = r.product_id
 AND ph.operation_type = r.operation_type
GROUP BY r.product_id, r.operator_id, r.operation_type;

COMMENT ON VIEW inventory_views.v_product_labor_by_operator IS
  'S-303: per prodotto, operatore e fase: tempo/pezzo e pezzi solo suoi (v_operator_labor_samples), IQR + winsor P5-P95, confronto con la mediana della stessa fase.';

GRANT SELECT ON inventory_views.v_operator_labor_samples TO planner_metriche;
GRANT SELECT ON inventory_views.v_product_phase_labor_stats TO planner_metriche;
GRANT SELECT ON inventory_views.v_product_labor_by_operator TO planner_metriche;
