-- ============================================================================
-- SCHEDULER F1 — OSSERVABILITÀ, CALIBRAZIONE E COLLEGAMENTO PIANO/REALTÀ
-- ============================================================================

ALTER TABLE "print-farm"."PrinterAssignment"
  ADD COLUMN "plannedStart" TIMESTAMPTZ(6),
  ADD COLUMN "plannedEnd" TIMESTAMPTZ(6),
  ADD COLUMN "plannedDurationMinutes" INTEGER;

CREATE INDEX "PrinterAssignment_plannedStart_idx"
  ON "print-farm"."PrinterAssignment"("plannedStart");

ALTER TABLE "print-farm"."GanttTask"
  ADD COLUMN "assignmentId" UUID;

CREATE INDEX "GanttTask_assignmentId_idx"
  ON "print-farm"."GanttTask"("assignmentId");

CREATE UNIQUE INDEX "GanttTask_ganttPlanId_assignmentId_key"
  ON "print-farm"."GanttTask"("ganttPlanId", "assignmentId");

ALTER TABLE "print-farm"."GanttTask"
  ADD CONSTRAINT "GanttTask_assignmentId_fkey"
  FOREIGN KEY ("assignmentId")
  REFERENCES "print-farm"."PrinterAssignment"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

CREATE TYPE "print-farm"."SchedulerInterventionType" AS ENUM (
  'FILAMENT_SWAP',
  'SPOOL_MOVE',
  'PLATE_CHANGE',
  'MANUAL_RETRY',
  'MANUAL_OVERRIDE'
);

CREATE TYPE "print-farm"."SchedulerInterventionSource" AS ENUM (
  'PLANNED',
  'UNPLANNED',
  'UNKNOWN'
);

CREATE TABLE "print-farm"."SchedulerCalibration" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "scopeKey" TEXT NOT NULL,
  "printerModelId" INTEGER NOT NULL,
  "materialCategory" TEXT NOT NULL,
  "fileId" UUID NOT NULL,
  "durationFactor" DECIMAL(10,6) NOT NULL DEFAULT 1,
  "filamentFactor" DECIMAL(10,6) NOT NULL DEFAULT 1,
  "failureRate" DECIMAL(10,6) NOT NULL DEFAULT 0,
  "sampleCount" INTEGER NOT NULL DEFAULT 0,
  "durationSampleCount" INTEGER NOT NULL DEFAULT 0,
  "filamentSampleCount" INTEGER NOT NULL DEFAULT 0,
  "failureSampleCount" INTEGER NOT NULL DEFAULT 0,
  "windowStart" TIMESTAMPTZ(6),
  "windowEnd" TIMESTAMPTZ(6),
  "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "SchedulerCalibration_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "SchedulerCalibration_scopeKey_key"
  ON "print-farm"."SchedulerCalibration"("scopeKey");
CREATE INDEX "SchedulerCalibration_printerModelId_materialCategory_idx"
  ON "print-farm"."SchedulerCalibration"("printerModelId", "materialCategory");
CREATE INDEX "SchedulerCalibration_fileId_idx"
  ON "print-farm"."SchedulerCalibration"("fileId");

ALTER TABLE "print-farm"."SchedulerCalibration"
  ADD CONSTRAINT "SchedulerCalibration_printerModelId_fkey"
  FOREIGN KEY ("printerModelId")
  REFERENCES "print-farm"."PrinterModel"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "print-farm"."SchedulerCalibration"
  ADD CONSTRAINT "SchedulerCalibration_fileId_fkey"
  FOREIGN KEY ("fileId")
  REFERENCES "print-farm"."ProjectThreeMFFile"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "print-farm"."SchedulerInterventionLog" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "eventKey" TEXT,
  "type" "print-farm"."SchedulerInterventionType" NOT NULL,
  "source" "print-farm"."SchedulerInterventionSource" NOT NULL DEFAULT 'UNKNOWN',
  "printerId" UUID,
  "assignmentId" UUID,
  "metadata" JSONB,
  "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "SchedulerInterventionLog_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "SchedulerInterventionLog_eventKey_key"
  ON "print-farm"."SchedulerInterventionLog"("eventKey");
CREATE INDEX "SchedulerInterventionLog_type_createdAt_idx"
  ON "print-farm"."SchedulerInterventionLog"("type", "createdAt");
CREATE INDEX "SchedulerInterventionLog_printerId_createdAt_idx"
  ON "print-farm"."SchedulerInterventionLog"("printerId", "createdAt");
CREATE INDEX "SchedulerInterventionLog_assignmentId_idx"
  ON "print-farm"."SchedulerInterventionLog"("assignmentId");

ALTER TABLE "print-farm"."SchedulerInterventionLog"
  ADD CONSTRAINT "SchedulerInterventionLog_printerId_fkey"
  FOREIGN KEY ("printerId")
  REFERENCES "print-farm"."Printer"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "print-farm"."SchedulerInterventionLog"
  ADD CONSTRAINT "SchedulerInterventionLog_assignmentId_fkey"
  FOREIGN KEY ("assignmentId")
  REFERENCES "print-farm"."PrinterAssignment"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

DROP VIEW IF EXISTS "print_farm_views"."v_pf_schedule_accuracy";

CREATE VIEW "print_farm_views"."v_pf_schedule_accuracy" AS
SELECT
  a."id" AS "assignmentId",
  gt."id" AS "ganttTaskId",
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
  COALESCE(gt."plannedStart" <= gt."horizonStart" + INTERVAL '24 hours', FALSE) AS "ganttWithin24h"
FROM "print-farm"."PrinterAssignment" a
JOIN "print-farm"."Printer" p ON p."id" = a."printerId"
LEFT JOIN LATERAL (
  SELECT
    t."id",
    t."plannedStart",
    gp."horizonStart"
  FROM "print-farm"."GanttTask" t
  JOIN "print-farm"."GanttPlan" gp ON gp."id" = t."ganttPlanId"
  WHERE t."assignmentId" = a."id"
  ORDER BY
    ABS(EXTRACT(EPOCH FROM (t."plannedStart" - a."plannedStart"))) ASC,
    gp."createdAt" DESC
  LIMIT 1
) gt ON TRUE
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
      THEN EXTRACT(EPOCH FROM (
        COALESCE(run."finishedAt", a."completedAt")
        - COALESCE(run."startedAt", a."startedAt")
      )) / 60.0
      ELSE NULL
    END
  ) AS actual_duration_minutes
) actual ON TRUE
WHERE a."plannedStart" IS NOT NULL
  AND a."plannedEnd" IS NOT NULL
  AND a."plannedDurationMinutes" IS NOT NULL;

COMMENT ON VIEW "print_farm_views"."v_pf_schedule_accuracy" IS
  'Accuratezza planned-vs-actual per assignment collegata al Gantt, inclusi tempi e filamento.';
