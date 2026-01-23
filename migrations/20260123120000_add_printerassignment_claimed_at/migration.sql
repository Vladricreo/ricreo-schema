-- Add a dedicated scheduler lock timestamp for PrinterAssignment.
-- `claimedAt` is used as a soft mutex ("STARTING" virtuale) and MUST NOT be used as real print start.
-- `startedAt` remains the real print start (on QUEUED -> PRINTING confirmation).

ALTER TABLE "print-farm"."PrinterAssignment"
ADD COLUMN IF NOT EXISTS "claimedAt" TIMESTAMPTZ(6);

-- Backfill legacy data:
-- historically the backend used `startedAt` as the claim lock for QUEUED assignments.
-- Move that value to `claimedAt` and reset `startedAt` to NULL so it regains "real start" semantics.
UPDATE "print-farm"."PrinterAssignment"
SET
  "claimedAt" = "startedAt",
  "startedAt" = NULL,
  "updatedAt" = now()
WHERE status = 'QUEUED'
  AND "claimedAt" IS NULL
  AND "startedAt" IS NOT NULL;

-- Index to speed up scheduling scans for eligible QUEUED assignments.
-- Query pattern: status='QUEUED' AND (claimedAt IS NULL OR claimedAt < now() - interval ...)
CREATE INDEX IF NOT EXISTS "PrinterAssignment_queued_claimedAt_idx"
ON "print-farm"."PrinterAssignment" ("claimedAt")
WHERE status = 'QUEUED';

