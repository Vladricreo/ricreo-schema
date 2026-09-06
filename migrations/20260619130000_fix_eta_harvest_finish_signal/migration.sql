-- ============================================================================
-- FIX SMART ETA — segnale di "fine stampa" per la latenza harvest
-- Problema: usavamo COALESCE(assignment.completedAt, printRun.finishedAt), ma
--   `assignment.completedAt` viene stampato al momento dello SCARICO (non della
--   fine stampa): la latenza risultava ~0 o negativa e veniva scartata dal filtro
--   (sample size ~3 su 6000+ harvest), forzando confidenza 'low' (bollino rosso).
-- Soluzione: usare PrintRun.finishedAt come segnale primario di fine stampa,
--   con fallback su assignment.completedAt solo se la run manca.
-- Column list invariata => CREATE OR REPLACE non rompe le view dipendenti.
-- ============================================================================
CREATE OR REPLACE VIEW "print_farm_views"."v_pf_harvest_latency_by_hour" AS
WITH events AS (
  SELECT
    COALESCE(pr."finishedAt", a."completedAt") AS finish_ts,
    EXTRACT(EPOCH FROM (h."harvestedAt" - COALESCE(pr."finishedAt", a."completedAt"))) / 60.0 AS latency_min
  FROM "print-farm"."PrinterHarvest" h
  JOIN "print-farm"."PrinterAssignment" a ON a."id" = h."assignmentId"
  LEFT JOIN "print-farm"."PrintRun" pr ON pr."id" = h."printRunId"
  WHERE h."harvestedAt" >= NOW() - INTERVAL '3 months'
),
clean AS (
  SELECT EXTRACT(HOUR FROM finish_ts)::INT AS finish_hour, latency_min
  FROM events
  WHERE finish_ts IS NOT NULL AND latency_min >= 0 AND latency_min <= 4320
)
SELECT
  finish_hour AS "finishHour",
  ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY latency_min)::NUMERIC, 2)  AS "medianLatencyMin",
  ROUND(percentile_cont(0.25) WITHIN GROUP (ORDER BY latency_min)::NUMERIC, 2) AS "p25LatencyMin",
  ROUND(percentile_cont(0.75) WITHIN GROUP (ORDER BY latency_min)::NUMERIC, 2) AS "p75LatencyMin",
  COUNT(*)::INT AS "sampleSize"
FROM clean
GROUP BY finish_hour;
