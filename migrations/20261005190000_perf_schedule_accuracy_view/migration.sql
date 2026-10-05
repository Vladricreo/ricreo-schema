-- Performance: v_pf_schedule_accuracy
--
-- Il LEFT JOIN LATERAL su GanttTask (≈25 task per assignment: ogni replan
-- copia i task) veniva eseguito anche quando la query non leggeva le colonne
-- Gantt. Il count della data-validation (`plan-vs-actual`) impiegava ~5,5s,
-- di cui ~4,8s nel lateral (66k righe GanttTask + 66k lookup GanttPlan).
--
-- Le due colonne Gantt diventano subquery scalari nella SELECT list: quando la
-- vista viene espansa Postgres scarta le colonne non referenziate, quindi la
-- subquery gira solo se il chiamante chiede "ganttTaskId"/"ganttWithin24h".
-- Stesse colonne, stessi tipi, stesso ordine → CREATE OR REPLACE.
-- Misurato sul DB live: count da 5,5s a 0,6s.

CREATE OR REPLACE VIEW "print_farm_views"."v_pf_schedule_accuracy" AS
SELECT
  a."id" AS "assignmentId",
  (
    SELECT t."id"
    FROM "print-farm"."GanttTask" t
    JOIN "print-farm"."GanttPlan" gp ON gp."id" = t."ganttPlanId"
    WHERE t."assignmentId" = a."id"
    ORDER BY
      ABS(EXTRACT(EPOCH FROM (t."plannedStart" - a."plannedStart"))) ASC,
      gp."createdAt" DESC
    LIMIT 1
  ) AS "ganttTaskId",
  a."printerId" AS "printerId",
  p."modelId" AS "printerModelId",
  a."productionJobId" AS "productionJobId",
  run."fileId" AS "fileId",
  a."materialRequired" AS "materialCategory",
  a."plannedStart" AS "plannedStart",
  a."plannedEnd" AS "plannedEnd",
  a."plannedDurationMinutes" AS "plannedDurationMinutes",
  COALESCE(run."startedAt", a."startedAt") AS "actualStart",
  COALESCE(run."finishedAt", a."completedAt") AS "actualEnd",
  actual.actual_duration_minutes::NUMERIC(14,4) AS "actualDurationMinutes",
  CASE
    WHEN COALESCE(run."startedAt", a."startedAt") IS NULL THEN NULL
    ELSE (EXTRACT(EPOCH FROM (COALESCE(run."startedAt", a."startedAt") - a."plannedStart")) / 60.0)::NUMERIC(14,4)
  END AS "startDeltaMinutes",
  CASE
    WHEN COALESCE(run."finishedAt", a."completedAt") IS NULL THEN NULL
    ELSE (EXTRACT(EPOCH FROM (COALESCE(run."finishedAt", a."completedAt") - a."plannedEnd")) / 60.0)::NUMERIC(14,4)
  END AS "endDeltaMinutes",
  CASE
    WHEN actual.actual_duration_minutes IS NULL THEN NULL
    ELSE (actual.actual_duration_minutes - a."plannedDurationMinutes")::NUMERIC(14,4)
  END AS "durationErrorMinutes",
  CASE
    WHEN actual.actual_duration_minutes IS NULL THEN NULL
    ELSE ABS(actual.actual_duration_minutes - a."plannedDurationMinutes")::NUMERIC(14,4)
  END AS "durationAbsErrorMinutes",
  CASE
    WHEN actual.actual_duration_minutes IS NULL OR a."plannedDurationMinutes" <= 0 THEN NULL
    ELSE (ABS(actual.actual_duration_minutes - a."plannedDurationMinutes") / a."plannedDurationMinutes" * 100)::NUMERIC(14,4)
  END AS "durationApePercent",
  run."expectedFilamentGrams"::NUMERIC(14,4) AS "expectedFilamentGrams",
  run."filamentUsedGrams"::NUMERIC(14,4) AS "actualFilamentGrams",
  CASE
    WHEN run."filamentUsedGrams" IS NULL OR run."expectedFilamentGrams" IS NULL THEN NULL
    ELSE (run."filamentUsedGrams" - run."expectedFilamentGrams")::NUMERIC(14,4)
  END AS "filamentErrorGrams",
  CASE
    WHEN run."filamentUsedGrams" IS NULL OR run."expectedFilamentGrams" IS NULL
      OR run."expectedFilamentGrams" <= 0 THEN NULL
    ELSE (ABS(run."filamentUsedGrams" - run."expectedFilamentGrams")
      / run."expectedFilamentGrams" * 100)::NUMERIC(14,4)
  END AS "filamentApePercent",
  COALESCE((
    SELECT t."plannedStart" <= gp."horizonStart" + INTERVAL '24 hours'
    FROM "print-farm"."GanttTask" t
    JOIN "print-farm"."GanttPlan" gp ON gp."id" = t."ganttPlanId"
    WHERE t."assignmentId" = a."id"
    ORDER BY
      ABS(EXTRACT(EPOCH FROM (t."plannedStart" - a."plannedStart"))) ASC,
      gp."createdAt" DESC
    LIMIT 1
  ), FALSE) AS "ganttWithin24h"
FROM "print-farm"."PrinterAssignment" a
JOIN "print-farm"."Printer" p ON p."id" = a."printerId"
LEFT JOIN LATERAL (
  SELECT
    r."fileId",
    r."startedAt",
    r."finishedAt",
    r."printTimeMinutes",
    m."expectedFilamentGrams",
    m."filamentUsedGrams"
  FROM "print-farm"."PrintRun" r
  LEFT JOIN "print-farm"."PrintRunMetrics" m ON m."printRunId" = r."id"
  WHERE r."assignmentId" = a."id"
  ORDER BY r."startedAt" DESC NULLS LAST, r."createdAt" DESC
  LIMIT 1
) run ON TRUE
LEFT JOIN LATERAL (
  SELECT COALESCE(
    run."printTimeMinutes"::NUMERIC,
    CASE
      WHEN COALESCE(run."startedAt", a."startedAt") IS NOT NULL
        AND COALESCE(run."finishedAt", a."completedAt") IS NOT NULL
      THEN EXTRACT(EPOCH FROM (COALESCE(run."finishedAt", a."completedAt") - COALESCE(run."startedAt", a."startedAt"))) / 60.0
      ELSE NULL
    END
  ) AS actual_duration_minutes
) actual ON TRUE
WHERE a."plannedStart" IS NOT NULL
  AND a."plannedEnd" IS NOT NULL
  AND a."plannedDurationMinutes" IS NOT NULL;
