-- ============================================================================
-- Viste print_farm_views: ripristino v_pf_job_eta + viste live senza migrazione
-- (REVISIONE 2026-09-30, finding V8-F2 e V8-F3; filone T7-MON)
--
-- 1) v_pf_job_eta: la definizione live aveva perso la confidenza "orizzonte +
--    segnali" della migrazione 20260619150000_eta_confidence_horizon perché
--    prisma/sql-runs/print_farm_views.sql (DROP + CREATE delle viste ETA) è
--    stato rieseguito dopo la migrazione: tutte le ETA risultavano 'medium'.
--    Qui si riapplica il corpo della 20260619150000 (stesse colonne, cambia
--    solo la CASE di "confidence" + la colonna interna exp_days) e sql-runs
--    è stato riallineato, così un nuovo re-run non riproduce la regressione.
--    v_pf_order_eta legge "confidence" da v_pf_job_eta: si corregge da sola.
--
-- 2) Viste usate dalla dashboard/Prisma che esistevano SOLO in sql-runs (un DB
--    costruito da `prisma migrate deploy` non le avrebbe): stesse definizioni
--    del live (verificate con pg_get_viewdef e commenti identici il
--    2026-10-06), copiate da sql-runs/print_farm_views.sql.
--    ESCLUSE di proposito: v_pf_locked_spools_for_swap (filone T4) e
--    v_pf_harvest_latency_by_hour (filone T5).
--
-- Idempotente: CREATE OR REPLACE con colonne, tipi e ordine invariati rispetto
-- al live (nessun DROP). Nessun dato toccato.
-- Applicabile anche via psql / Supabase SQL editor; in quel caso:
--   bunx prisma migrate resolve --applied 20261006152000_pf_views_job_eta_and_untracked
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) v_pf_job_eta (corpo della 20260619150000_eta_confidence_horizon)
-- ----------------------------------------------------------------------------
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

-- ----------------------------------------------------------------------------
-- 2) Viste live senza migrazione (definizioni da sql-runs = live)
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- v_pf_kpi_totals_30d
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW "print_farm_views"."v_pf_kpi_totals_30d" AS
WITH cost_cfg AS (
  SELECT
    COALESCE( (s."settings"->>'value')::NUMERIC, 0.25 ) AS cost_per_kwh
  FROM "print-farm"."Settings" s
  WHERE s."settingsname" = 'energy_cost'
    AND s."settingstype" = 'COST_PER_KWH'
  LIMIT 1
),
energy_30d AS (
  SELECT
    COALESCE(SUM(e."kwh")::NUMERIC, 0) AS kwh
  FROM "print-farm"."PrinterEnergyDailySlice" e
  WHERE e."day" >= (CURRENT_DATE - INTERVAL '29 days')::DATE
),
runs_30d AS (
  SELECT
    r.*,
    CASE
      WHEN r."status" = 'FAILED' THEN
        CEIL(
          GREATEST(COALESCE(f."partCount", r."quantityFailed", 0), 0)::NUMERIC
          * LEAST(1, GREATEST(0, COALESCE(r."completionPercent", 0)::NUMERIC / 100))
        )::INT
      ELSE COALESCE(r."quantityFailed", 0)
    END AS "effectiveFailedQty"
  FROM "print-farm"."PrintRun" r
  LEFT JOIN "print-farm"."ProjectThreeMFFile" f ON f."id" = r."fileId"
  WHERE r."finishedAt" >= NOW() - INTERVAL '30 days'
    AND r."status" IN ('COMPLETED', 'FAILED')
)
SELECT
  COALESCE(COUNT(*)::INT, 0) AS "printsCount",
  COALESCE(SUM(r."quantitySuccess")::INT, 0) AS "successQty",
  COALESCE(SUM(r."effectiveFailedQty")::INT, 0) AS "failedQty",
  CASE
    WHEN COALESCE(SUM(r."quantitySuccess") + SUM(r."effectiveFailedQty"), 0) = 0 THEN 0
    ELSE ROUND(
      (SUM(r."effectiveFailedQty")::NUMERIC / NULLIF(SUM(r."quantitySuccess") + SUM(r."effectiveFailedQty"), 0)) * 100,
      2
    )
  END AS "failureRatePct",
  COALESCE(ROUND(AVG(r."printTimeMinutes")::NUMERIC, 2), 0) AS "avgPrintTimeMin",
  COALESCE(ROUND((SELECT kwh FROM energy_30d), 3), 0) AS "kwh",
  COALESCE(ROUND((SELECT kwh FROM energy_30d) * (SELECT cost_per_kwh FROM cost_cfg), 2), 0) AS "energyCost"
FROM runs_30d r;

COMMENT ON VIEW "print_farm_views"."v_pf_kpi_totals_30d" IS
  'KPI aggregati print farm ultimi 30 giorni. failedQty/failureRatePct usano lo scarto effettivo (quantityFailed scalato per completionPercent sulle run FAILED), non il valore grezzo che spesso vale l''intero partCount anche a bassa % di completamento.';

-- ----------------------------------------------------------------------------
-- v_pf_prints_daily_90d
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW "print_farm_views"."v_pf_prints_daily_90d" AS
WITH date_series AS (
  SELECT generate_series(
    (CURRENT_DATE - INTERVAL '89 days')::DATE,
    CURRENT_DATE,
    '1 day'::INTERVAL
  )::DATE AS day
),
daily_parts AS (
  SELECT
    DATE(r."finishedAt") AS day,
    COALESCE(SUM(r."quantitySuccess"), 0)::INT AS success_qty,
    COALESCE(SUM(
      CASE
        WHEN r."status" = 'FAILED' THEN
          CEIL(
            GREATEST(COALESCE(f."partCount", r."quantityFailed", 0), 0)::NUMERIC
            * LEAST(1, GREATEST(0, COALESCE(r."completionPercent", 0)::NUMERIC / 100))
          )
        ELSE COALESCE(r."quantityFailed", 0)
      END
    ), 0)::INT AS failed_qty
  FROM "print-farm"."PrintRun" r
  LEFT JOIN "print-farm"."ProjectThreeMFFile" f ON f."id" = r."fileId"
  WHERE r."finishedAt" >= (CURRENT_DATE - INTERVAL '89 days')::TIMESTAMP
    AND r."status" IN ('COMPLETED', 'FAILED')
  GROUP BY DATE(r."finishedAt")
),
daily_energy AS (
  SELECT
    e."day" AS day,
    COALESCE(SUM(e."kwh")::NUMERIC, 0) AS kwh
  FROM "print-farm"."PrinterEnergyDailySlice" e
  WHERE e."day" >= (CURRENT_DATE - INTERVAL '89 days')::DATE
  GROUP BY e."day"
)
SELECT
  ds.day,
  COALESCE(dp.success_qty, 0) AS "successQty",
  COALESCE(dp.failed_qty, 0) AS "failedQty",
  COALESCE(ROUND(de.kwh, 3), 0) AS "kwh"
FROM date_series ds
LEFT JOIN daily_parts dp ON dp.day = ds.day
LEFT JOIN daily_energy de ON de.day = ds.day
ORDER BY ds.day;

COMMENT ON VIEW "print_farm_views"."v_pf_prints_daily_90d" IS
  'Pezzi giornalieri OK/scartati + kWh farm (PrinterEnergyDailySlice) per trend 90 giorni.';

-- ----------------------------------------------------------------------------
-- v_pf_utilization_daily_30d
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW "print_farm_views"."v_pf_utilization_daily_30d" AS
WITH date_series AS (
  SELECT generate_series(
    (CURRENT_DATE - INTERVAL '29 days')::DATE,
    CURRENT_DATE,
    '1 day'::INTERVAL
  )::DATE AS day
),
printer_count AS (
  -- Numero di stampanti non in manutenzione/disabilitate
  SELECT COUNT(*)::INT AS total
  FROM "print-farm"."Printer"
  WHERE "manualOverrideStatus" IS NULL
),
daily_runs AS (
  -- Usa printTimeMinutes se valorizzato, altrimenti durata da startedAt/finishedAt (minuti)
  SELECT
    DATE(r."finishedAt") AS day,
    COALESCE(
      SUM(COALESCE(r."printTimeMinutes"::NUMERIC, EXTRACT(EPOCH FROM (r."finishedAt" - r."startedAt")) / 60))::NUMERIC,
      0
    ) AS run_minutes
  FROM "print-farm"."PrintRun" r
  WHERE r."finishedAt" >= NOW() - INTERVAL '30 days'
    AND r."status" IN ('COMPLETED', 'FAILED', 'IN_PROGRESS')
  GROUP BY DATE(r."finishedAt")
)
SELECT
  ds.day,
  COALESCE(dr.run_minutes, 0) AS "runMinutes",
  CASE
    WHEN pc.total = 0 THEN 0
    ELSE ROUND(
      (COALESCE(dr.run_minutes, 0) / NULLIF(pc.total * 1440, 0)) * 100,
      2
    )
  END AS "utilizationPct"
FROM date_series ds
CROSS JOIN printer_count pc
LEFT JOIN daily_runs dr ON dr.day = ds.day
ORDER BY ds.day;

COMMENT ON VIEW "print_farm_views"."v_pf_utilization_daily_30d" IS
  'Utilizzo giornaliero stampanti (minuti run e % capacità) per BarGraph.';

-- ----------------------------------------------------------------------------
-- v_pf_issues_open_by_category
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW "print_farm_views"."v_pf_issues_open_by_category" AS
SELECT
  ec."category"::text AS "category",
  COUNT(*)::INT AS "openCount",
  0::INT AS "ackedCount",
  COUNT(*) FILTER (WHERE ec."severity" = 'CRITICAL')::INT AS "criticalCount"
FROM "print-farm"."PrinterLogs" pl
JOIN "print-farm"."ErrorCode" ec ON ec."id" = pl."errorCodeId"
WHERE ec."category" <> 'IGNORE'
  AND COALESCE(pl."occurredAt", pl."createdAt") >= NOW() - INTERVAL '7 days'
GROUP BY ec."category"
ORDER BY "openCount" DESC;

COMMENT ON VIEW "print_farm_views"."v_pf_issues_open_by_category" IS
  'Issue per categoria ErrorCode (BLOCKING / RECOVERABLE / WARNING / FILAMENT_RUNOUT) aggregate da PrinterLogs, finestra ultimi 7 giorni (fixedAt non viene mai scritto quindi non e'' usabile come stato "aperta").';

-- ----------------------------------------------------------------------------
-- v_pf_failures_by_reason_30d
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW "print_farm_views"."v_pf_failures_by_reason_30d" AS
WITH runs_with_effective_scrap AS (
  SELECT
    pr."printerId",
    CASE
      WHEN pr."status" = 'FAILED' THEN
        CEIL(
          GREATEST(COALESCE(f."partCount", pr."quantityFailed", 0), 0)::NUMERIC
          * LEAST(1, GREATEST(0, COALESCE(pr."completionPercent", 0)::NUMERIC / 100))
        )::INT
      ELSE COALESCE(pr."quantityFailed", 0)
    END AS "effectiveFailedQty"
  FROM "print-farm"."PrintRun" pr
  LEFT JOIN "print-farm"."ProjectThreeMFFile" f ON f."id" = pr."fileId"
  WHERE pr."finishedAt" >= NOW() - INTERVAL '30 days'
)
SELECT
  p."name" AS "reason",
  COALESCE(SUM(rs."effectiveFailedQty"), 0)::INT AS "scrappedQty",
  COUNT(*) FILTER (WHERE rs."effectiveFailedQty" > 0)::INT AS "eventsCount"
FROM runs_with_effective_scrap rs
JOIN "print-farm"."Printer" p ON p."id" = rs."printerId"
WHERE rs."effectiveFailedQty" > 0
GROUP BY p."name"
ORDER BY "scrappedQty" DESC;

COMMENT ON VIEW "print_farm_views"."v_pf_failures_by_reason_30d" IS
  'Top stampanti per pezzi scartati ultimi 30 giorni (scarto effettivo: quantityFailed scalato per completionPercent sulle run FAILED). Il campo reason contiene il nome stampante.';

-- ----------------------------------------------------------------------------
-- v_pf_recent_activity
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW "print_farm_views"."v_pf_recent_activity" AS
(
  -- Issue (da PrinterLogs, join su ErrorCode per categoria/severity/descrizione)
  SELECT
    ('ISSUE:' || pl."id"::TEXT) AS "id",
    'ISSUE' AS "type",
    COALESCE(pl."occurredAt", pl."createdAt") AS "at",
    CONCAT('Issue: ', ec."category"::TEXT) AS "title",
    COALESCE(ec."description", ec."code", 'Nessun dettaglio') AS "subtitle",
    ec."severity"::TEXT AS "severity",
    p."name" AS "printerName"
  FROM "print-farm"."PrinterLogs" pl
  JOIN "print-farm"."ErrorCode" ec ON ec."id" = pl."errorCodeId"
  LEFT JOIN "print-farm"."Printer" p ON p."id" = pl."printerId"
  WHERE ec."category" <> 'IGNORE'
    AND COALESCE(pl."occurredAt", pl."createdAt") >= NOW() - INTERVAL '7 days'
)
UNION ALL
(
  -- Manutenzione
  SELECT
    ('MAINTENANCE:' || m."id"::TEXT) AS "id",
    'MAINTENANCE' AS "type",
    m."performedAt" AS "at",
    CONCAT('Manutenzione: ', m."type") AS "title",
    m."description" AS "subtitle",
    'WARNING' AS "severity",
    p."name" AS "printerName"
  FROM "print-farm"."PrinterMaintenanceLog" m
  JOIN "print-farm"."Printer" p ON p."id" = m."printerId"
  WHERE m."performedAt" >= NOW() - INTERVAL '7 days'
)
ORDER BY "at" DESC
LIMIT 20;

COMMENT ON VIEW "print_farm_views"."v_pf_recent_activity" IS
  'Attività recente unificata (issue da PrinterLogs / manutenzione) per widget. Il ramo failure (PrintFailureLog) è stato rimosso perché mai popolato.';

-- ----------------------------------------------------------------------------
-- v_pf_maintenance_monthly
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW "print_farm_views"."v_pf_maintenance_monthly" AS
SELECT
  DATE_TRUNC('month', m."performedAt")::DATE AS "month",
  COALESCE(SUM(m."cost")::NUMERIC, 0) AS "totalCost",
  COALESCE(SUM(m."durationMin")::INT, 0) AS "totalMinutes",
  COUNT(*)::INT AS "interventionsCount"
FROM "print-farm"."PrinterMaintenanceLog" m
WHERE m."performedAt" >= NOW() - INTERVAL '12 months'
GROUP BY DATE_TRUNC('month', m."performedAt")
ORDER BY "month";

COMMENT ON VIEW "print_farm_views"."v_pf_maintenance_monthly" IS
  'Costo e durata manutenzione aggregati per mese (ultimi 12 mesi).';

-- ----------------------------------------------------------------------------
-- v_pf_energy_daily_30d
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW "print_farm_views"."v_pf_energy_daily_30d" AS
WITH cost_cfg AS (
  SELECT
    COALESCE( (s."settings"->>'value')::NUMERIC, 0.25 ) AS cost_per_kwh
  FROM "print-farm"."Settings" s
  WHERE s."settingsname" = 'energy_cost'
    AND s."settingstype" = 'COST_PER_KWH'
  LIMIT 1
),
date_series AS (
  SELECT generate_series(
    (CURRENT_DATE - INTERVAL '29 days')::DATE,
    CURRENT_DATE,
    '1 day'::INTERVAL
  )::DATE AS day
),
daily_energy AS (
  SELECT
    e."day" AS day,
    COALESCE(SUM(e."kwh")::NUMERIC, 0) AS kwh
  FROM "print-farm"."PrinterEnergyDailySlice" e
  WHERE e."day" >= (CURRENT_DATE - INTERVAL '29 days')::DATE
  GROUP BY e."day"
)
SELECT
  ds.day,
  COALESCE(ROUND(de.kwh, 3), 0) AS "kwh",
  COALESCE(ROUND(COALESCE(de.kwh, 0) * (SELECT cost_per_kwh FROM cost_cfg), 2), 0) AS "energyCost"
FROM date_series ds
LEFT JOIN daily_energy de ON de.day = ds.day
ORDER BY ds.day;

COMMENT ON VIEW "print_farm_views"."v_pf_energy_daily_30d" IS
  'Consumo energia giornaliero (kWh e costo) per trend (30 giorni).';

-- ----------------------------------------------------------------------------
-- v_pf_filament_consumption_30d
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW "print_farm_views"."v_pf_filament_consumption_30d" AS
SELECT
  COALESCE(fm."filamentType", c."name", 'N/A') AS "category",
  COALESCE(fm."colorUsed", 'N/A') AS "color",
  COALESCE(SUM(
    CASE
      WHEN r."status" = 'COMPLETED' THEN fm."usedWeight"
      WHEN r."status" = 'FAILED' THEN
        fm."usedWeight"
        * LEAST(
            1::numeric,
            GREATEST(0::numeric, COALESCE(r."completionPercent", 0)::numeric / 100)
          )
      ELSE 0::numeric
    END
  )::NUMERIC, 0) AS "estimatedGrams",
  COUNT(DISTINCT r."id")::INT AS "runsCount"
FROM "print-farm"."PrintRun" r
JOIN "print-farm"."ProjectThreeMFFile" f ON f."id" = r."fileId"
JOIN "print-farm"."ProjectFileMaterial" fm ON fm."fileId" = f."id"
LEFT JOIN "inventory"."Item" i ON i."id" = fm."materialId"
LEFT JOIN "inventory"."Category" c ON c."id" = i."categoryId"
WHERE r."finishedAt" >= NOW() - INTERVAL '30 days'
  AND r."status" IN ('COMPLETED', 'FAILED')
  AND fm."usedWeight" IS NOT NULL
  AND fm."usedWeight" > 0
GROUP BY COALESCE(fm."filamentType", c."name", 'N/A'), COALESCE(fm."colorUsed", 'N/A')
ORDER BY "estimatedGrams" DESC;

COMMENT ON VIEW "print_farm_views"."v_pf_filament_consumption_30d" IS
  'Consumo filamento stimato (grammi plate 3MF) per categoria e colore (ultimi 30 giorni). COMPLETED = peso plate; FAILED = peso × completionPercent. Non usa remainingWeight bobine.';
