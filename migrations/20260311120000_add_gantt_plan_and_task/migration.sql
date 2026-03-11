-- Migration: add_gantt_plan_and_task
-- Reactive Gantt Scheduler: tabelle per pianificazione a orizzonte temporale.

-- Enum: GanttPlanStatus
CREATE TYPE "print-farm"."GanttPlanStatus" AS ENUM ('ACTIVE', 'SUPERSEDED', 'FAILED');

-- Enum: GanttTaskStatus
CREATE TYPE "print-farm"."GanttTaskStatus" AS ENUM ('PLANNED', 'IN_PROGRESS', 'COMPLETED', 'SKIPPED', 'DELAYED');

-- Table: GanttPlan
CREATE TABLE "print-farm"."GanttPlan" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "status" "print-farm"."GanttPlanStatus" NOT NULL DEFAULT 'ACTIVE',
    "horizonStart" TIMESTAMPTZ(6) NOT NULL,
    "horizonEnd" TIMESTAMPTZ(6) NOT NULL,
    "solverStatus" TEXT,
    "solverObjective" DECIMAL(16,2),
    "solverDurationMs" INTEGER,
    "jobsEvaluated" INTEGER NOT NULL DEFAULT 0,
    "printersEvaluated" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT now(),
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT now(),

    CONSTRAINT "GanttPlan_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "GanttPlan_status_idx" ON "print-farm"."GanttPlan"("status");
CREATE INDEX "GanttPlan_createdAt_idx" ON "print-farm"."GanttPlan"("createdAt");

-- Table: GanttTask
CREATE TABLE "print-farm"."GanttTask" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "ganttPlanId" UUID NOT NULL,
    "printerId" UUID NOT NULL,
    "productionJobId" UUID,
    "productOrderId" UUID,
    "plannedStart" TIMESTAMPTZ(6) NOT NULL,
    "plannedEnd" TIMESTAMPTZ(6) NOT NULL,
    "durationMinutes" INTEGER NOT NULL,
    "sequenceIndex" INTEGER NOT NULL DEFAULT 0,
    "isSetup" BOOLEAN NOT NULL DEFAULT false,
    "materialCategory" TEXT,
    "colorHex" TEXT,
    "partsExpected" INTEGER NOT NULL DEFAULT 0,
    "taskStatus" "print-farm"."GanttTaskStatus" NOT NULL DEFAULT 'PLANNED',
    "label" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT now(),
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT now(),

    CONSTRAINT "GanttTask_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "GanttTask_ganttPlanId_idx" ON "print-farm"."GanttTask"("ganttPlanId");
CREATE INDEX "GanttTask_printerId_idx" ON "print-farm"."GanttTask"("printerId");
CREATE INDEX "GanttTask_productionJobId_idx" ON "print-farm"."GanttTask"("productionJobId");
CREATE INDEX "GanttTask_productOrderId_idx" ON "print-farm"."GanttTask"("productOrderId");
CREATE INDEX "GanttTask_taskStatus_idx" ON "print-farm"."GanttTask"("taskStatus");
CREATE INDEX "GanttTask_plannedStart_idx" ON "print-farm"."GanttTask"("plannedStart");

-- Foreign keys
ALTER TABLE "print-farm"."GanttTask"
    ADD CONSTRAINT "GanttTask_ganttPlanId_fkey"
    FOREIGN KEY ("ganttPlanId") REFERENCES "print-farm"."GanttPlan"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "print-farm"."GanttTask"
    ADD CONSTRAINT "GanttTask_printerId_fkey"
    FOREIGN KEY ("printerId") REFERENCES "print-farm"."Printer"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "print-farm"."GanttTask"
    ADD CONSTRAINT "GanttTask_productionJobId_fkey"
    FOREIGN KEY ("productionJobId") REFERENCES "print-farm"."ProductionJob"("id")
    ON DELETE SET NULL ON UPDATE CASCADE;
