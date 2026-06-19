-- ============================================================================
-- FIX SMART ETA — confidenza basata su orizzonte + segnali concreti
-- Problema: la confidenza era 'high' solo con copertura Gantt >= 0.8. Poiche'
--   il piano Gantt attivo copre solo job gia' FULFILLED (coverage 0 sugli attivi),
--   TUTTI i job risultavano 'medium' (bollino arancione), a prescindere dalla
--   bonta' della stima.
-- Soluzione: la confidenza riflette quanto e' affidabile l'ETA:
--   - alta  : job pianificato dal Gantt (>=0.8) OPPURE che finisce a breve
--             (entro ~2 giorni) con campione harvest solido;
--   - bassa : campione harvest scarso OPPURE orizzonte molto lontano (>~10 giorni);
--   - media : tutti gli altri.
--   Razionale: le stime a breve sono affidabili; quelle lontane vengono spesso
--   stravolte da nuovi ordini/priorita'.
-- Column list invariata => CREATE OR REPLACE non rompe v_pf_order_eta.
-- ============================================================================
CREATE OR REPLACE VIEW "print_farm_views"."v_pf_job_eta" AS
WITH cfg AS (
  SELECT COALESCE(MAX(v."valueNum"), 6)::NUMERIC AS max_printers_per_job
  FROM "print-farm"."SchedulerConfigValue" v
  JOIN "print-farm"."SchedulerConfigProfile" p
    ON p."id" = v."profileId" AND p."status" = 'ACTIVE'
  WHERE v."key" = 'MAX_PRINTERS_PER_JOB'
),
harvest AS (
  SELECT
    COALESCE(SUM("sampleSize" * "medianLatencyMin") / NULLIF(SUM("sampleSize"), 0), 10)::NUMERIC AS exp_min,
    COALESCE(MIN("medianLatencyMin") FILTER (WHERE "sampleSize" >= 5), 5)::NUMERIC AS opt_min,
    COALESCE(MAX("medianLatencyMin") FILTER (WHERE "sampleSize" >= 5), 20)::NUMERIC AS pes_min,
    COALESCE(SUM("sampleSize"), 0)::INT AS sample_size
  FROM "print_farm_views"."v_pf_harvest_latency_by_hour"
),
fleet AS (
  SELECT COALESCE(MAX("activePrinters"), 1)::INT AS active_printers
  FROM "print_farm_views"."v_pf_fleet_throughput_monthly"
  WHERE "month" >= (date_trunc('month', NOW()) - INTERVAL '3 months')::DATE
),
jobs AS (
  SELECT
    j."id" AS job_id,
    j."number" AS job_number,
    j."priority" AS priority,
    j."productOrderId" AS product_order_id,
    j."createdAt" AS created_at,
    GREATEST(0, j."quantity" - j."quantityPrinted") AS remaining_qty,
    COALESCE(array_length(j."assignedPrinterIds", 1), 0) AS assigned_count
  FROM "print-farm"."ProductionJob" j
  WHERE j."status" IN ('READY_TO_PRODUCE', 'NEEDS_CONFIGURATION', 'AWAITING_RESOURCES', 'IN_PROGRESS')
    AND j."quantity" > j."quantityPrinted"
),
job_work AS (
  SELECT
    jb.job_id, jb.job_number, jb.priority, jb.product_order_id, jb.created_at,
    jb.remaining_qty, jb.assigned_count,
    SUM(CEIL(jb.remaining_qty::NUMERIC / GREATEST(1, f."partCount")) * f."estimatedDurationMinutes")::NUMERIC AS work_minutes,
    SUM(CEIL(jb.remaining_qty::NUMERIC / GREATEST(1, f."partCount")))::NUMERIC AS plates_remaining
  FROM jobs jb
  JOIN "print-farm"."_JobsToFiles" jf ON jf."A" = jb.job_id
  JOIN "print-farm"."ProjectThreeMFFile" f ON f."id" = jf."B"
  GROUP BY jb.job_id, jb.job_number, jb.priority, jb.product_order_id, jb.created_at, jb.remaining_qty, jb.assigned_count
),
gantt AS (
  SELECT
    t."productionJobId" AS job_id,
    MAX(t."plannedEnd") AS scheduled_end,
    COALESCE(SUM(t."partsExpected"), 0) AS parts_scheduled
  FROM "print-farm"."GanttTask" t
  JOIN "print-farm"."GanttPlan" gp ON gp."id" = t."ganttPlanId" AND gp."status" = 'ACTIVE'
  WHERE t."isSetup" = FALSE AND t."productionJobId" IS NOT NULL
  GROUP BY t."productionJobId"
),
prio_tot AS (
  SELECT priority, SUM(work_minutes) AS w, SUM(plates_remaining) AS p
  FROM job_work GROUP BY priority
),
ordered AS (
  SELECT jw.*,
    SUM(jw.work_minutes) OVER win AS cum_work_incl,
    SUM(jw.plates_remaining) OVER win AS cum_plates_incl
  FROM job_work jw
  WINDOW win AS (ORDER BY jw.priority DESC, jw.created_at ASC, jw.job_number ASC)
),
unassigned AS (
  SELECT GREATEST(1, COUNT(*))::NUMERIC AS c FROM job_work WHERE assigned_count = 0
),
calc AS (
  SELECT
    o.*,
    g.scheduled_end,
    LEAST(1.0, COALESCE(g.parts_scheduled, 0)::NUMERIC / NULLIF(o.remaining_qty, 0))::NUMERIC AS covered_fraction,
    COALESCE((SELECT SUM(w) FROM prio_tot pt WHERE pt.priority > o.priority), 0)::NUMERIC AS higher_work,
    COALESCE((SELECT SUM(p) FROM prio_tot pt WHERE pt.priority > o.priority), 0)::NUMERIC AS higher_plates,
    COALESCE((SELECT w FROM prio_tot pt WHERE pt.priority = o.priority), o.work_minutes)::NUMERIC AS same_work,
    COALESCE((SELECT p FROM prio_tot pt WHERE pt.priority = o.priority), o.plates_remaining)::NUMERIC AS same_plates,
    h.exp_min AS h_exp, h.opt_min AS h_opt, h.pes_min AS h_pes, h.sample_size,
    fl.active_printers, cfg.max_printers_per_job, u.c AS unassigned_count
  FROM ordered o
  LEFT JOIN gantt g ON g.job_id = o.job_id
  CROSS JOIN harvest h
  CROSS JOIN fleet fl
  CROSS JOIN cfg
  CROSS JOIN unassigned u
),
final AS (
  SELECT c.*,
    GREATEST(1, c.active_printers)::NUMERIC AS fleet,
    LEAST(GREATEST(1, c.plates_remaining), c.max_printers_per_job)::NUMERIC AS opt_printers,
    CASE
      WHEN c.assigned_count > 0 THEN LEAST(c.assigned_count, c.max_printers_per_job::INT)
      ELSE GREATEST(1, LEAST(c.max_printers_per_job::INT,
        FLOOR(c.active_printers::NUMERIC / c.unassigned_count)::INT))
    END::NUMERIC AS exp_printers,
    (c.work_minutes * (1 - c.covered_fraction)) AS tail_work,
    (c.plates_remaining * (1 - c.covered_fraction)) AS tail_plates,
    -- orizzonte atteso in giorni (coerente con etaExpected) per la confidenza
    CASE WHEN c.scheduled_end IS NOT NULL
      THEN GREATEST(0, EXTRACT(EPOCH FROM (c.scheduled_end - NOW())) / 86400)
      ELSE (c.cum_work_incl + c.cum_plates_incl * c.h_exp) / GREATEST(1, c.active_printers) / 1440.0
    END AS exp_days
  FROM calc c
)
SELECT
  f.job_id AS "jobId",
  f.job_number::TEXT AS "jobNumber",
  f.product_order_id AS "productOrderId",
  f.priority AS "priority",
  f.remaining_qty AS "remainingQty",
  ROUND(f.plates_remaining)::INT AS "platesRemaining",
  ROUND(f.work_minutes, 2) AS "workMinutes",
  f.scheduled_end AS "scheduledEnd",
  ROUND(f.covered_fraction, 3) AS "ganttCoverage",
  f.exp_printers::INT AS "expectedPrinters",
  ROUND(f.h_exp, 1) AS "harvestPerPlateMin",
  ROUND(f.higher_work / f.fleet, 1) AS "queueWaitExpectedMin",
  CASE WHEN f.scheduled_end IS NOT NULL THEN
    f.scheduled_end + make_interval(secs => (((f.tail_work + f.tail_plates * f.h_opt) / f.opt_printers) * 60)::DOUBLE PRECISION)
  ELSE
    NOW() + make_interval(secs => (GREATEST(
      (f.work_minutes + f.plates_remaining * f.h_opt) / f.opt_printers,
      ((f.higher_work + f.work_minutes) + (f.higher_plates + f.plates_remaining) * f.h_opt) / f.fleet
    ) * 60)::DOUBLE PRECISION)
  END AS "etaOptimistic",
  CASE WHEN f.scheduled_end IS NOT NULL THEN
    f.scheduled_end + make_interval(secs => (((f.tail_work + f.tail_plates * f.h_exp) / f.exp_printers) * 60)::DOUBLE PRECISION)
  ELSE
    NOW() + make_interval(secs => (((f.cum_work_incl + f.cum_plates_incl * f.h_exp) / f.fleet) * 60)::DOUBLE PRECISION)
  END AS "etaExpected",
  CASE WHEN f.scheduled_end IS NOT NULL THEN
    f.scheduled_end + make_interval(secs => ((f.tail_work + f.tail_plates * f.h_pes) * 60)::DOUBLE PRECISION)
  ELSE
    NOW() + make_interval(secs => ((((f.higher_work + f.same_work) + (f.higher_plates + f.same_plates) * f.h_pes) / f.fleet) * 60)::DOUBLE PRECISION)
  END AS "etaPessimistic",
  -- Confidenza: orizzonte + segnali concreti (Gantt, campione harvest)
  CASE
    WHEN f.sample_size < 10 AND f.covered_fraction < 0.3 THEN 'low'
    WHEN f.covered_fraction >= 0.8 OR (f.exp_days <= 2 AND f.sample_size >= 30) THEN 'high'
    WHEN f.exp_days > 10 THEN 'low'
    ELSE 'medium'
  END AS "confidence",
  CASE
    WHEN f.scheduled_end IS NULL THEN 'throughput'
    WHEN f.covered_fraction >= 1 THEN 'gantt'
    ELSE 'gantt+throughput'
  END AS "basis"
FROM final f;
