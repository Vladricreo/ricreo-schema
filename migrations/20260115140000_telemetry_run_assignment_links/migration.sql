-- Add robust correlations for telemetry events (run/assignment).
-- This enables reliable debugging/analytics when taskId arrives late or services reboot.

-- ============================
-- PrinterStateEvent
-- ============================
ALTER TABLE "print-farm"."PrinterStateEvent"
  ADD COLUMN IF NOT EXISTS "printRunId" uuid,
  ADD COLUMN IF NOT EXISTS "assignmentId" uuid;

ALTER TABLE "print-farm"."PrinterStateEvent"
  ADD CONSTRAINT "PrinterStateEvent_printRunId_fkey"
    FOREIGN KEY ("printRunId")
    REFERENCES "print-farm"."PrintRun"("id")
    ON DELETE SET NULL
    ON UPDATE CASCADE;

ALTER TABLE "print-farm"."PrinterStateEvent"
  ADD CONSTRAINT "PrinterStateEvent_assignmentId_fkey"
    FOREIGN KEY ("assignmentId")
    REFERENCES "print-farm"."PrinterAssignment"("id")
    ON DELETE SET NULL
    ON UPDATE CASCADE;

CREATE INDEX IF NOT EXISTS "PrinterStateEvent_printRunId_at_idx"
  ON "print-farm"."PrinterStateEvent" ("printRunId", "at" DESC);

CREATE INDEX IF NOT EXISTS "PrinterStateEvent_assignmentId_at_idx"
  ON "print-farm"."PrinterStateEvent" ("assignmentId", "at" DESC);

-- ============================
-- PrinterDowntimeEvent
-- ============================
ALTER TABLE "print-farm"."PrinterDowntimeEvent"
  ADD COLUMN IF NOT EXISTS "printRunId" uuid,
  ADD COLUMN IF NOT EXISTS "assignmentId" uuid;

ALTER TABLE "print-farm"."PrinterDowntimeEvent"
  ADD CONSTRAINT "PrinterDowntimeEvent_printRunId_fkey"
    FOREIGN KEY ("printRunId")
    REFERENCES "print-farm"."PrintRun"("id")
    ON DELETE SET NULL
    ON UPDATE CASCADE;

ALTER TABLE "print-farm"."PrinterDowntimeEvent"
  ADD CONSTRAINT "PrinterDowntimeEvent_assignmentId_fkey"
    FOREIGN KEY ("assignmentId")
    REFERENCES "print-farm"."PrinterAssignment"("id")
    ON DELETE SET NULL
    ON UPDATE CASCADE;

CREATE INDEX IF NOT EXISTS "PrinterDowntimeEvent_printRunId_openedAt_idx"
  ON "print-farm"."PrinterDowntimeEvent" ("printRunId", "openedAt" DESC);

CREATE INDEX IF NOT EXISTS "PrinterDowntimeEvent_assignmentId_openedAt_idx"
  ON "print-farm"."PrinterDowntimeEvent" ("assignmentId", "openedAt" DESC);

