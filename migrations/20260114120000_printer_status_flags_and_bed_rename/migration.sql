-- Printer: rename bedOccupied* -> hasCompletedPrintOnBed* + add needsFilamentSwap
-- + remove TO_HARVEST / FILAMENT_SWAP_NEEDED from PrinterOperationalStatus
-- + add MANUAL_PRINTING to PrinterManualOverrideStatus

-- Views may depend on old column names
DROP VIEW IF EXISTS "print_farm_views"."v_pf_printer_status_summary";
-- This view depends on Printer.operationalStatus (enum). We must drop it before altering the enum type.
DROP VIEW IF EXISTS "print_farm_views"."v_pf_printers_by_operational_status";

-- ============================================================================
-- Rename columns (physical DB rename)
-- ============================================================================

ALTER TABLE "print-farm"."Printer" RENAME COLUMN "bedOccupied" TO "hasCompletedPrintOnBed";
ALTER TABLE "print-farm"."Printer" RENAME COLUMN "bedOccupiedAt" TO "hasCompletedPrintOnBedAt";
ALTER TABLE "print-farm"."Printer" RENAME COLUMN "bedOccupiedAssignmentId" TO "hasCompletedPrintOnBedAssignmentId";

-- Rename indexes / constraints for consistency (optional but reduces drift)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'print-farm' AND c.relname = 'Printer_bedOccupied_idx'
  ) THEN
    ALTER INDEX "print-farm"."Printer_bedOccupied_idx" RENAME TO "Printer_hasCompletedPrintOnBed_idx";
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'print-farm' AND c.relname = 'Printer_bedOccupiedAssignmentId_key'
  ) THEN
    ALTER INDEX "print-farm"."Printer_bedOccupiedAssignmentId_key" RENAME TO "Printer_hasCompletedPrintOnBedAssignmentId_key";
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_constraint con
    JOIN pg_class rel ON rel.oid = con.conrelid
    JOIN pg_namespace n ON n.oid = rel.relnamespace
    WHERE n.nspname = 'print-farm'
      AND rel.relname = 'Printer'
      AND con.conname = 'Printer_bedOccupiedAssignmentId_fkey'
  ) THEN
    ALTER TABLE "print-farm"."Printer"
      RENAME CONSTRAINT "Printer_bedOccupiedAssignmentId_fkey"
      TO "Printer_hasCompletedPrintOnBedAssignmentId_fkey";
  END IF;
END $$;

-- Add new overlay flag for filament swap (idempotent)
ALTER TABLE "print-farm"."Printer"
  ADD COLUMN IF NOT EXISTS "needsFilamentSwap" BOOLEAN NOT NULL DEFAULT false;

-- ============================================================================
-- Data backfill before enum change
-- ============================================================================

UPDATE "print-farm"."Printer"
SET "hasCompletedPrintOnBed" = true
WHERE ("operationalStatus"::text) = 'TO_HARVEST'
  AND "hasCompletedPrintOnBed" IS DISTINCT FROM true;

UPDATE "print-farm"."Printer"
SET "needsFilamentSwap" = true
WHERE ("operationalStatus"::text) = 'FILAMENT_SWAP_NEEDED'
  AND "needsFilamentSwap" IS DISTINCT FROM true;

-- Normalize legacy operationalStatus values to base values (so enum cast succeeds)
UPDATE "print-farm"."Printer"
SET "operationalStatus" = 'AVAILABLE'::"print-farm"."PrinterOperationalStatus"
WHERE ("operationalStatus"::text) = 'TO_HARVEST';

UPDATE "print-farm"."Printer"
SET "operationalStatus" = 'NEEDS_SETUP'::"print-farm"."PrinterOperationalStatus"
WHERE ("operationalStatus"::text) = 'FILAMENT_SWAP_NEEDED';

-- ============================================================================
-- PrinterOperationalStatus: remove TO_HARVEST / FILAMENT_SWAP_NEEDED
-- PostgreSQL doesn't support DROP VALUE on enum => recreate the enum
-- ============================================================================

CREATE TYPE "print-farm"."PrinterOperationalStatus_new" AS ENUM (
  'AVAILABLE',
  'QUEUED',
  'PRINTING',
  'NEEDS_SETUP',
  'FILAMENT_RUNOUT',
  'ERROR'
);

ALTER TABLE "print-farm"."Printer"
  ALTER COLUMN "operationalStatus" DROP DEFAULT;

ALTER TABLE "print-farm"."Printer"
  ALTER COLUMN "operationalStatus" TYPE "print-farm"."PrinterOperationalStatus_new"
  USING ("operationalStatus"::text::"print-farm"."PrinterOperationalStatus_new");

ALTER TYPE "print-farm"."PrinterOperationalStatus" RENAME TO "PrinterOperationalStatus_old";
ALTER TYPE "print-farm"."PrinterOperationalStatus_new" RENAME TO "PrinterOperationalStatus";
DROP TYPE "print-farm"."PrinterOperationalStatus_old";

ALTER TABLE "print-farm"."Printer"
  ALTER COLUMN "operationalStatus" SET DEFAULT 'AVAILABLE'::"print-farm"."PrinterOperationalStatus";

-- ============================================================================
-- PrinterManualOverrideStatus: add MANUAL_PRINTING
-- ============================================================================

ALTER TYPE "print-farm"."PrinterManualOverrideStatus" ADD VALUE IF NOT EXISTS 'MANUAL_PRINTING';

-- ============================================================================
-- Recreate view(s) with new column name
-- ============================================================================

CREATE VIEW "print_farm_views"."v_pf_printer_status_summary" AS
SELECT id AS "printerId",
    name AS "printerName",
    status AS "wssStatus",
    "operationalStatus",
    "manualOverrideStatus",
    "hasCompletedPrintOnBed",
    "needsFilamentSwap",
    ( SELECT count(*)::integer AS count
           FROM "print-farm"."PrinterIssue" i
          WHERE i."printerId" = p.id AND (i.status = ANY (ARRAY['OPEN'::"print-farm"."PrinterIssueStatus", 'ACKED'::"print-farm"."PrinterIssueStatus"]))) AS "openIssuesCount",
    ( SELECT r."finishedAt"
           FROM "print-farm"."PrintRun" r
             JOIN "print-farm"."PrinterAssignment" a ON a.id = r."assignmentId"
          WHERE a."printerId" = p.id
          ORDER BY r."finishedAt" DESC
         LIMIT 1) AS "lastRunFinishedAt"
FROM "print-farm"."Printer" p
ORDER BY name;

-- Recreate view that aggregates printers by operationalStatus (dropped before enum change)
CREATE OR REPLACE VIEW "print_farm_views"."v_pf_printers_by_operational_status" AS
SELECT
  p."operationalStatus" AS "operationalStatus",
  COUNT(*)::INT AS "count"
FROM "print-farm"."Printer" p
GROUP BY p."operationalStatus"
ORDER BY "count" DESC;

