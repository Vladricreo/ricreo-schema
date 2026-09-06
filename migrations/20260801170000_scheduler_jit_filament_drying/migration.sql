-- Drying JIT: policy materiale esplicita e ciclo persistente per bobina fisica.
CREATE TYPE "print-farm"."FilamentDryingPolicy" AS ENUM (
  'NONE',
  'RECOMMENDED',
  'REQUIRED'
);

CREATE TYPE "print-farm"."AssignmentDryingPlanStatus" AS ENUM (
  'PLANNED',
  'AWAITING_OPERATOR',
  'DRYING',
  'READY',
  'CONSUMED',
  'EXPIRED',
  'CANCELLED',
  'FAILED'
);

ALTER TYPE "print-farm"."SchedulerInterventionType"
  ADD VALUE IF NOT EXISTS 'FILAMENT_DRYING';

ALTER TABLE "print-farm"."FilamentProfile"
  ADD COLUMN "dryingPolicy" "print-farm"."FilamentDryingPolicy" NOT NULL DEFAULT 'NONE',
  ADD COLUMN "dryingFreshnessHours" INTEGER,
  ADD COLUMN "requireAmsHtForPrint" BOOLEAN NOT NULL DEFAULT false;

-- Il warning legacy conserva la propria semantica non bloccante.
UPDATE "print-farm"."FilamentProfile"
SET "dryingPolicy" = 'RECOMMENDED'
WHERE "warnDryOpenedSpoolBeforePrint" = true;

ALTER TABLE "print-farm"."FilamentProfile"
  ADD CONSTRAINT "FilamentProfile_dryingFreshnessHours_check"
  CHECK ("dryingFreshnessHours" IS NULL OR "dryingFreshnessHours" > 0);

COMMENT ON COLUMN "print-farm"."FilamentProfile"."dryingPolicy"
  IS 'Policy pre-stampa: NONE, RECOMMENDED (warning) o REQUIRED (blocco finché READY e fresca).';
COMMENT ON COLUMN "print-farm"."FilamentProfile"."dryingFreshnessHours"
  IS 'Ore di validità dopo completamento confermato; null usa il default scheduler.';
COMMENT ON COLUMN "print-farm"."FilamentProfile"."requireAmsHtForPrint"
  IS 'Vincolo percorso separato: la stampa deve alimentarsi esclusivamente da AMS HT.';
COMMENT ON COLUMN "print-farm"."FilamentProfile"."requireHeatedAmsForPrint"
  IS 'Flag legacy preservato senza cambio semantico; accetta AMS riscaldata compatibile.';

CREATE TABLE "print-farm"."AssignmentDryingPlan" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "assignmentId" UUID NOT NULL,
  "spoolPlanId" UUID NOT NULL,
  "spoolId" UUID NOT NULL,
  "printerId" UUID NOT NULL,
  "amsUnitId" UUID NOT NULL,
  "amsSlotId" UUID NOT NULL,
  "ganttPlanId" UUID,
  "ganttTaskId" UUID,
  "fileFilamentIndex" INTEGER NOT NULL,
  "extruderId" INTEGER,
  "routingReason" TEXT,
  "policy" "print-farm"."FilamentDryingPolicy" NOT NULL,
  "status" "print-farm"."AssignmentDryingPlanStatus" NOT NULL DEFAULT 'PLANNED',
  "tempC" INTEGER NOT NULL,
  "durationMinutes" INTEGER NOT NULL,
  "freshnessHours" INTEGER NOT NULL,
  "plannedStart" TIMESTAMPTZ(6) NOT NULL,
  "plannedEnd" TIMESTAMPTZ(6) NOT NULL,
  "dueBefore" TIMESTAMPTZ(6) NOT NULL,
  "freshnessUntil" TIMESTAMPTZ(6),
  "operatorConfirmedAt" TIMESTAMPTZ(6),
  "startedAt" TIMESTAMPTZ(6),
  "completedAt" TIMESTAMPTZ(6),
  "stoppedAt" TIMESTAMPTZ(6),
  "commandIdempotencyKey" TEXT,
  "commandVersion" INTEGER NOT NULL DEFAULT 1,
  "planVersion" INTEGER NOT NULL DEFAULT 1,
  "plannedBy" TEXT NOT NULL DEFAULT 'scheduler-drying-v1',
  "failureReason" TEXT,
  "metadata" JSONB,
  "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "AssignmentDryingPlan_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "AssignmentDryingPlan_temperature_check" CHECK ("tempC" > 0 AND "tempC" <= 85),
  CONSTRAINT "AssignmentDryingPlan_duration_check" CHECK ("durationMinutes" > 0),
  CONSTRAINT "AssignmentDryingPlan_freshness_check" CHECK ("freshnessHours" > 0),
  CONSTRAINT "AssignmentDryingPlan_window_check" CHECK ("plannedStart" < "plannedEnd" AND "plannedEnd" <= "dueBefore")
);

CREATE UNIQUE INDEX "AssignmentDryingPlan_commandIdempotencyKey_key"
  ON "print-farm"."AssignmentDryingPlan"("commandIdempotencyKey");
CREATE UNIQUE INDEX "AssignmentDryingPlan_assignmentId_spoolPlanId_planVersion_key"
  ON "print-farm"."AssignmentDryingPlan"("assignmentId", "spoolPlanId", "planVersion");
CREATE INDEX "AssignmentDryingPlan_assignmentId_status_idx"
  ON "print-farm"."AssignmentDryingPlan"("assignmentId", "status");
CREATE INDEX "AssignmentDryingPlan_spoolId_status_idx"
  ON "print-farm"."AssignmentDryingPlan"("spoolId", "status");
CREATE INDEX "AssignmentDryingPlan_printerId_status_idx"
  ON "print-farm"."AssignmentDryingPlan"("printerId", "status");
CREATE INDEX "AssignmentDryingPlan_amsUnitId_plannedStart_plannedEnd_idx"
  ON "print-farm"."AssignmentDryingPlan"("amsUnitId", "plannedStart", "plannedEnd");
CREATE INDEX "AssignmentDryingPlan_amsSlotId_status_idx"
  ON "print-farm"."AssignmentDryingPlan"("amsSlotId", "status");
CREATE INDEX "AssignmentDryingPlan_ganttTaskId_idx"
  ON "print-farm"."AssignmentDryingPlan"("ganttTaskId");
CREATE INDEX "AssignmentDryingPlan_status_dueBefore_idx"
  ON "print-farm"."AssignmentDryingPlan"("status", "dueBefore");
CREATE INDEX "AssignmentDryingPlan_freshnessUntil_idx"
  ON "print-farm"."AssignmentDryingPlan"("freshnessUntil");

ALTER TABLE "print-farm"."AssignmentDryingPlan"
  ADD CONSTRAINT "AssignmentDryingPlan_assignmentId_fkey"
  FOREIGN KEY ("assignmentId") REFERENCES "print-farm"."PrinterAssignment"("id")
  ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT "AssignmentDryingPlan_spoolPlanId_fkey"
  FOREIGN KEY ("spoolPlanId") REFERENCES "print-farm"."AssignmentSpoolPlan"("id")
  ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT "AssignmentDryingPlan_spoolId_fkey"
  FOREIGN KEY ("spoolId") REFERENCES "print-farm"."FilamentSpool"("id")
  ON DELETE RESTRICT ON UPDATE CASCADE,
  ADD CONSTRAINT "AssignmentDryingPlan_printerId_fkey"
  FOREIGN KEY ("printerId") REFERENCES "print-farm"."Printer"("id")
  ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT "AssignmentDryingPlan_amsUnitId_fkey"
  FOREIGN KEY ("amsUnitId") REFERENCES "print-farm"."PrinterAmsUnit"("id")
  ON DELETE RESTRICT ON UPDATE CASCADE,
  ADD CONSTRAINT "AssignmentDryingPlan_amsSlotId_fkey"
  FOREIGN KEY ("amsSlotId") REFERENCES "print-farm"."PrinterAmsSlot"("id")
  ON DELETE RESTRICT ON UPDATE CASCADE,
  ADD CONSTRAINT "AssignmentDryingPlan_ganttPlanId_fkey"
  FOREIGN KEY ("ganttPlanId") REFERENCES "print-farm"."GanttPlan"("id")
  ON DELETE SET NULL ON UPDATE CASCADE,
  ADD CONSTRAINT "AssignmentDryingPlan_ganttTaskId_fkey"
  FOREIGN KEY ("ganttTaskId") REFERENCES "print-farm"."GanttTask"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;
