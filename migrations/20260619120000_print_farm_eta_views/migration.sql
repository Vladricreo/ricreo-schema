-- ============================================================================
-- PRINT FARM — SMART ETA VIEWS
-- Schema: "print_farm_views"
-- Descrizione: View read-only per stimare la data di completamento (ETA) di
--   ogni ProductionJob e di ogni ProductOrder. Modello "ibrido":
--     1) parte gia schedulata  -> letta dal Gantt (GanttTask.plannedEnd)
--     2) backlog oltre orizzonte -> stima statistica (throughput + harvest)
--   L'ETA e espressa come banda (ottimistica / attesa / pessimistica).
-- Le stime sono "data-driven": la latenza di harvest deriva dalla
-- distribuzione storica per ora del giorno (effetto notte incluso).
-- ============================================================================

-- Drop in ordine inverso di dipendenza (order_eta dipende da job_eta, ecc.)
DROP VIEW IF EXISTS "print_farm_views"."v_pf_order_eta";
DROP VIEW IF EXISTS "print_farm_views"."v_pf_job_eta";
DROP VIEW IF EXISTS "print_farm_views"."v_pf_harvest_latency_by_hour";
DROP VIEW IF EXISTS "print_farm_views"."v_pf_fleet_throughput_monthly";

-- ============================================================================
-- 1. v_pf_harvest_latency_by_hour
-- Latenza di harvest (fine stampa -> raccolta pezzi) in minuti, mediana per
-- ora del giorno in cui la stampa e terminata, ultimi 3 mesi.
-- Cattura l'effetto "di notte le stampanti non vengono scaricate".
-- ============================================================================
CREATE VIEW "print_farm_views"."v_pf_harvest_latency_by_hour" AS
WITH events AS (
  SELECT
    -- istante di fine stampa: preferisci l'assignment, fallback sulla run
    COALESCE(a."completedAt", pr."finishedAt") AS finish_ts,
    EXTRACT(EPOCH FROM (h."harvestedAt" - COALESCE(a."completedAt", pr."finishedAt"))) / 60.0 AS latency_min
  FROM "print-farm"."PrinterHarvest" h
  JOIN "print-farm"."PrinterAssignment" a ON a."id" = h."assignmentId"
  LEFT JOIN "print-farm"."PrintRun" pr ON pr."id" = h."printRunId"
  WHERE h."harvestedAt" >= NOW() - INTERVAL '3 months'
),
clean AS (
  SELECT
    EXTRACT(HOUR FROM finish_ts)::INT AS finish_hour,
    latency_min
  FROM events
  -- scarta dati anomali / clock skew; tieni fino a 72h (week-end realistici)
  WHERE finish_ts IS NOT NULL
    AND latency_min >= 0
    AND latency_min <= 4320
)
SELECT
  finish_hour AS "finishHour",
  ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY latency_min)::NUMERIC, 2)  AS "medianLatencyMin",
  ROUND(percentile_cont(0.25) WITHIN GROUP (ORDER BY latency_min)::NUMERIC, 2) AS "p25LatencyMin",
  ROUND(percentile_cont(0.75) WITHIN GROUP (ORDER BY latency_min)::NUMERIC, 2) AS "p75LatencyMin",
  COUNT(*)::INT AS "sampleSize"
FROM clean
GROUP BY finish_hour;

COMMENT ON VIEW "print_farm_views"."v_pf_harvest_latency_by_hour" IS
  'Latenza harvest (fine->raccolta) mediana per ora del giorno, ultimi 3 mesi.';

-- ============================================================================
-- 2. v_pf_fleet_throughput_monthly
-- Utilizzo mensile della flotta: minuti di stampa vs capacita disponibile.
-- Espone anche la capacita libera (% e stampanti attive) usata per stimare
-- quante stampanti un job potra realisticamente "prendere".
-- ============================================================================
CREATE VIEW "print_farm_views"."v_pf_fleet_throughput_monthly" AS
WITH months AS (
  SELECT generate_series(
    date_trunc('month', NOW()) - INTERVAL '11 months',
    date_trunc('month', NOW()),
    INTERVAL '1 month'
  ) AS month_start
),
active_printers AS (
  -- stampanti non in manutenzione/disabilitate (coerente con la view giornaliera)
  SELECT COUNT(*)::INT AS total
  FROM "print-farm"."Printer"
  WHERE "manualOverrideStatus" IS NULL
),
monthly_runs AS (
  SELECT
    date_trunc('month', r."finishedAt") AS month_start,
    COALESCE(SUM(COALESCE(
      r."printTimeMinutes"::NUMERIC,
      EXTRACT(EPOCH FROM (r."finishedAt" - r."startedAt")) / 60.0
    )), 0)::NUMERIC AS run_minutes
  FROM "print-farm"."PrintRun" r
  WHERE r."finishedAt" >= date_trunc('month', NOW()) - INTERVAL '11 months'
    AND r."status" IN ('COMPLETED', 'FAILED', 'IN_PROGRESS')
  GROUP BY 1
)
SELECT
  m.month_start::DATE AS "month",
  COALESCE(mr.run_minutes, 0)::NUMERIC(14, 2) AS "runMinutes",
  -- capacita = stampanti attive * minuti trascorsi nel mese (cap a NOW per il mese corrente)
  (ap.total * EXTRACT(EPOCH FROM (
    LEAST(NOW(), m.month_start + INTERVAL '1 month') - m.month_start
  )) / 60.0)::NUMERIC(14, 2) AS "capacityMinutes",
  CASE
    WHEN ap.total = 0 THEN 0
    ELSE LEAST(100, ROUND(
      COALESCE(mr.run_minutes, 0) / NULLIF(
        ap.total * EXTRACT(EPOCH FROM (
          LEAST(NOW(), m.month_start + INTERVAL '1 month') - m.month_start
        )) / 60.0, 0
      ) * 100, 2
    ))
  END AS "utilizationPct",
  CASE
    WHEN ap.total = 0 THEN 100
    ELSE GREATEST(0, 100 - LEAST(100, ROUND(
      COALESCE(mr.run_minutes, 0) / NULLIF(
        ap.total * EXTRACT(EPOCH FROM (
          LEAST(NOW(), m.month_start + INTERVAL '1 month') - m.month_start
        )) / 60.0, 0
      ) * 100, 2
    )))
  END AS "freeCapacityPct",
  ap.total AS "activePrinters"
FROM months m
CROSS JOIN active_printers ap
LEFT JOIN monthly_runs mr ON mr.month_start = m.month_start;

COMMENT ON VIEW "print_farm_views"."v_pf_fleet_throughput_monthly" IS
  'Utilizzo mensile flotta (minuti stampa, capacita, % libera, stampanti attive).';

-- ============================================================================
-- 3. v_pf_job_eta
-- ETA per ogni ProductionJob attivo, come banda (ottimistica/attesa/pessimistica).
-- Ibrido: ancora al Gantt per la parte schedulata, throughput per il resto.
-- ============================================================================
CREATE VIEW "print_farm_views"."v_pf_job_eta" AS
WITH cfg AS (
  -- massimo numero di stampanti per job dal profilo scheduler ACTIVE (fallback 6)
  SELECT COALESCE(MAX(v."valueNum"), 6)::NUMERIC AS max_printers_per_job
  FROM "print-farm"."SchedulerConfigValue" v
  JOIN "print-farm"."SchedulerConfigProfile" p
    ON p."id" = v."profileId" AND p."status" = 'ACTIVE'
  WHERE v."key" = 'MAX_PRINTERS_PER_JOB'
),
harvest AS (
  -- sintesi data-driven della latenza harvest dalla view per-ora
  SELECT
    COALESCE(SUM("sampleSize" * "medianLatencyMin") / NULLIF(SUM("sampleSize"), 0), 10)::NUMERIC AS exp_min,
    COALESCE(MIN("medianLatencyMin") FILTER (WHERE "sampleSize" >= 5), 5)::NUMERIC AS opt_min,
    COALESCE(MAX("medianLatencyMin") FILTER (WHERE "sampleSize" >= 5), 20)::NUMERIC AS pes_min,
    COALESCE(SUM("sampleSize"), 0)::INT AS sample_size
  FROM "print_farm_views"."v_pf_harvest_latency_by_hour"
),
fleet AS (
  -- capacita libera media (ultimi 3 mesi) e numero stampanti attive
  SELECT
    COALESCE(AVG("freeCapacityPct"), 30)::NUMERIC AS free_pct,
    COALESCE(MAX("activePrinters"), 1)::INT AS active_printers
  FROM "print_farm_views"."v_pf_fleet_throughput_monthly"
  WHERE "month" >= (date_trunc('month', NOW()) - INTERVAL '3 months')::DATE
),
jobs AS (
  SELECT
    j."id" AS job_id,
    j."number" AS job_number,
    j."priority" AS priority,
    j."productOrderId" AS product_order_id,
    GREATEST(0, j."quantity" - j."quantityPrinted") AS remaining_qty,
    COALESCE(array_length(j."assignedPrinterIds", 1), 0) AS assigned_count
  FROM "print-farm"."ProductionJob" j
  WHERE j."status" IN ('READY_TO_PRODUCE', 'NEEDS_CONFIGURATION', 'AWAITING_RESOURCES', 'IN_PROGRESS')
    AND j."quantity" > j."quantityPrinted"
),
job_work AS (
  -- lavoro residuo: somma su tutti i file collegati (stesso criterio della UI)
  SELECT
    jb.job_id, jb.job_number, jb.priority, jb.product_order_id,
    jb.remaining_qty, jb.assigned_count,
    SUM(CEIL(jb.remaining_qty::NUMERIC / GREATEST(1, f."partCount")) * f."estimatedDurationMinutes")::NUMERIC AS work_minutes,
    SUM(CEIL(jb.remaining_qty::NUMERIC / GREATEST(1, f."partCount")))::NUMERIC AS plates_remaining
  FROM jobs jb
  JOIN "print-farm"."_JobsToFiles" jf ON jf."A" = jb.job_id
  JOIN "print-farm"."ProjectThreeMFFile" f ON f."id" = jf."B"
  GROUP BY jb.job_id, jb.job_number, jb.priority, jb.product_order_id, jb.remaining_qty, jb.assigned_count
),
gantt AS (
  -- copertura dal piano Gantt ATTIVO (solo task di stampa, non setup)
  SELECT
    t."productionJobId" AS job_id,
    MAX(t."plannedEnd") AS scheduled_end,
    COALESCE(SUM(t."partsExpected"), 0) AS parts_scheduled
  FROM "print-farm"."GanttTask" t
  JOIN "print-farm"."GanttPlan" gp ON gp."id" = t."ganttPlanId" AND gp."status" = 'ACTIVE'
  WHERE t."isSetup" = FALSE AND t."productionJobId" IS NOT NULL
  GROUP BY t."productionJobId"
),
unassigned AS (
  SELECT GREATEST(1, COUNT(*))::NUMERIC AS c FROM job_work WHERE assigned_count = 0
),
contention AS (
  -- attesa per priorita: lavoro dei job a priorita maggiore (e >=) gia in coda
  SELECT
    a.job_id,
    COALESCE(SUM(b.work_minutes) FILTER (WHERE b.priority > a.priority), 0)::NUMERIC AS higher_work,
    COALESCE(SUM(b.work_minutes) FILTER (WHERE b.priority >= a.priority), 0)::NUMERIC AS ge_work
  FROM job_work a
  LEFT JOIN job_work b ON b.job_id <> a.job_id
  GROUP BY a.job_id
),
calc AS (
  SELECT
    jw.job_id, jw.job_number, jw.priority, jw.product_order_id,
    jw.remaining_qty, jw.assigned_count, jw.work_minutes, jw.plates_remaining,
    g.scheduled_end,
    LEAST(1.0, COALESCE(g.parts_scheduled, 0)::NUMERIC / NULLIF(jw.remaining_qty, 0))::NUMERIC AS covered_fraction,
    c.higher_work, c.ge_work,
    h.exp_min AS h_exp, h.opt_min AS h_opt, h.pes_min AS h_pes, h.sample_size,
    fl.free_pct, fl.active_printers,
    cfg.max_printers_per_job,
    u.c AS unassigned_count
  FROM job_work jw
  LEFT JOIN gantt g ON g.job_id = jw.job_id
  LEFT JOIN contention c ON c.job_id = jw.job_id
  CROSS JOIN harvest h
  CROSS JOIN fleet fl
  CROSS JOIN cfg
  CROSS JOIN unassigned u
),
final AS (
  SELECT
    job_id, job_number, product_order_id, priority, remaining_qty,
    plates_remaining, work_minutes, scheduled_end, covered_fraction,
    h_opt, h_exp, h_pes, sample_size, active_printers, free_pct, max_printers_per_job,
    -- lavoro residuo oltre la copertura del Gantt
    (work_minutes * (1 - covered_fraction)) AS tail_work,
    (plates_remaining * (1 - covered_fraction)) AS tail_plates,
    -- stampanti per ciascun limite della banda
    LEAST(GREATEST(1, plates_remaining), max_printers_per_job) AS opt_printers,
    CASE
      WHEN assigned_count > 0 THEN LEAST(assigned_count, max_printers_per_job::INT)
      ELSE GREATEST(1, LEAST(max_printers_per_job::INT,
        FLOOR(active_printers * free_pct / 100.0 / unassigned_count)::INT))
    END AS exp_printers,
    1 AS pes_printers,
    -- attesa in coda (solo se il job non e ancora nel Gantt)
    CASE WHEN scheduled_end IS NULL
      THEN higher_work / GREATEST(1, active_printers * free_pct / 100.0)
      ELSE 0 END AS exp_wait,
    CASE WHEN scheduled_end IS NULL THEN ge_work ELSE 0 END AS pes_wait
  FROM calc
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
  f.exp_printers AS "expectedPrinters",
  ROUND(f.h_exp, 1) AS "harvestPerPlateMin",
  ROUND(f.exp_wait, 1) AS "queueWaitExpectedMin",
  COALESCE(f.scheduled_end, NOW())
    + make_interval(secs => (((f.tail_work + f.tail_plates * f.h_opt) / f.opt_printers) * 60)::DOUBLE PRECISION) AS "etaOptimistic",
  COALESCE(f.scheduled_end, NOW() + make_interval(secs => (f.exp_wait * 60)::DOUBLE PRECISION))
    + make_interval(secs => (((f.tail_work + f.tail_plates * f.h_exp) / f.exp_printers) * 60)::DOUBLE PRECISION) AS "etaExpected",
  COALESCE(f.scheduled_end, NOW() + make_interval(secs => (f.pes_wait * 60)::DOUBLE PRECISION))
    + make_interval(secs => (((f.tail_work + f.tail_plates * f.h_pes) / f.pes_printers) * 60)::DOUBLE PRECISION) AS "etaPessimistic",
  CASE
    WHEN f.covered_fraction >= 0.8 AND f.sample_size >= 30 THEN 'high'
    WHEN f.covered_fraction >= 0.3 OR f.sample_size >= 10 THEN 'medium'
    ELSE 'low'
  END AS "confidence",
  CASE
    WHEN f.scheduled_end IS NULL THEN 'throughput'
    WHEN f.covered_fraction >= 1 THEN 'gantt'
    ELSE 'gantt+throughput'
  END AS "basis"
FROM final f;

COMMENT ON VIEW "print_farm_views"."v_pf_job_eta" IS
  'ETA per ProductionJob attivo (banda ottimistica/attesa/pessimistica), ibrido Gantt + throughput.';

-- ============================================================================
-- 4. v_pf_order_eta
-- ETA per ProductOrder = massimo tra le ETA dei job figli (l'ordine finisce
-- quando finisce la parte piu lenta). Confidenza = livello minimo dei job.
-- ============================================================================
CREATE VIEW "print_farm_views"."v_pf_order_eta" AS
SELECT
  je."productOrderId" AS "orderId",
  o."number"::TEXT AS "orderNumber",
  o."quantityToProduce" AS "quantityToProduce",
  o."quantityProduced" AS "quantityProduced",
  o."productionStatus"::TEXT AS "productionStatus",
  COUNT(*)::INT AS "jobsCount",
  MAX(je."etaOptimistic") AS "etaOptimistic",
  MAX(je."etaExpected") AS "etaExpected",
  MAX(je."etaPessimistic") AS "etaPessimistic",
  CASE
    WHEN bool_or(je."confidence" = 'low') THEN 'low'
    WHEN bool_or(je."confidence" = 'medium') THEN 'medium'
    ELSE 'high'
  END AS "confidence"
FROM "print_farm_views"."v_pf_job_eta" je
JOIN "inventory"."ProductOrder" o ON o."id" = je."productOrderId"
WHERE je."productOrderId" IS NOT NULL
GROUP BY je."productOrderId", o."number", o."quantityToProduce", o."quantityProduced", o."productionStatus";

COMMENT ON VIEW "print_farm_views"."v_pf_order_eta" IS
  'ETA per ProductOrder = max(ETA job figli); confidenza = livello minimo.';
