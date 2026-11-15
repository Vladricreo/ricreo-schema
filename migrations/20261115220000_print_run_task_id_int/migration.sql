-- PrintRun.taskId da SMALLINT a INTEGER (15/11, L-4 dell'audit Bambuddy, A-373).
-- Con MQTT_UNIQUE_TASK_ID acceso il backend manda task_id in secondi dal 1970
-- (~1,79e9): non entra in SMALLINT e l'aggancio PrintRun ⇄ stampa salta.
-- Additiva: allargare il tipo non cambia nessun valore (oggi |taskId| <= 30000).
--
-- La view print_farm_views.v_pf_kpi_totals_30d legge la colonna (r.*), e
-- Postgres non cambia il tipo di una colonna usata da una view: si toglie e si
-- ricrea uguale (stessa definizione di client/prisma/sql-runs/print_farm_views.sql,
-- stesse colonne in uscita, stesso commento, stesso permesso a planner_metriche).
-- Nessun'altra view dipende da lei (controllato su pg_depend il 15/11).
--
-- Dopo l'applicazione: alzare PRINT_RUN_TASK_ID_MAX in
-- backend/src/utils/normalization.js a 2147483647.

DROP VIEW "print_farm_views"."v_pf_kpi_totals_30d";

-- AlterTable
ALTER TABLE "print-farm"."PrintRun" ALTER COLUMN "taskId" SET DATA TYPE INTEGER;

CREATE VIEW "print_farm_views"."v_pf_kpi_totals_30d" AS
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

GRANT SELECT ON "print_farm_views"."v_pf_kpi_totals_30d" TO planner_metriche;
