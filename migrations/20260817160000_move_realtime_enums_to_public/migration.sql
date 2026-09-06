-- Sposta gli enum usati dalle tabelle in `supabase_realtime` da
-- "print-farm"."PascalCase" a public.snake_case.
-- Motivo: wal2json emette `"type":"print-farm"."PrinterBrand"` (JSON invalido)
-- e Realtime `list_changes` fallisce (22P02, Token "."). Lo schema realtime
-- non è scrivibile dal SQL Editor, quindi si sistema il tipo PG.

-- View che dipendono dai tipi: si ricreano dopo lo spostamento.
DROP VIEW IF EXISTS "print_farm_views"."v_pf_printer_status_summary";
DROP VIEW IF EXISTS "print_farm_views"."v_pf_printers_by_operational_status";

ALTER TYPE "print-farm"."PrinterBrand" SET SCHEMA public;
ALTER TYPE public."PrinterBrand" RENAME TO printer_brand;

ALTER TYPE "print-farm"."SoftwareType" SET SCHEMA public;
ALTER TYPE public."SoftwareType" RENAME TO software_type;

ALTER TYPE "print-farm"."PrinterStatus" SET SCHEMA public;
ALTER TYPE public."PrinterStatus" RENAME TO printer_status;

ALTER TYPE "print-farm"."PrinterOperationalStatus" SET SCHEMA public;
ALTER TYPE public."PrinterOperationalStatus" RENAME TO printer_operational_status;

ALTER TYPE "print-farm"."PrinterManualOverrideStatus" SET SCHEMA public;
ALTER TYPE public."PrinterManualOverrideStatus" RENAME TO printer_manual_override_status;

ALTER TYPE "print-farm"."AmsModel" SET SCHEMA public;
ALTER TYPE public."AmsModel" RENAME TO ams_model;

ALTER TYPE "print-farm"."PlateType" SET SCHEMA public;
ALTER TYPE public."PlateType" RENAME TO plate_type;

ALTER TYPE "print-farm"."AssignmentStatus" SET SCHEMA public;
ALTER TYPE public."AssignmentStatus" RENAME TO assignment_status;

ALTER TYPE "print-farm"."QueueTaskStatus" SET SCHEMA public;
ALTER TYPE public."QueueTaskStatus" RENAME TO queue_task_status;

CREATE VIEW "print_farm_views"."v_pf_printers_by_operational_status" AS
SELECT
  p."operationalStatus" AS "operationalStatus",
  COUNT(*)::INT AS "count"
FROM "print-farm"."Printer" p
WHERE p."manualOverrideStatus" IS DISTINCT FROM 'DISABLED'
GROUP BY p."operationalStatus"
ORDER BY "count" DESC;

COMMENT ON VIEW "print_farm_views"."v_pf_printers_by_operational_status" IS
  'Distribuzione stampanti per stato operativo (PieGraph). Esclude le stampanti dismesse (manualOverrideStatus=DISABLED).';

CREATE VIEW "print_farm_views"."v_pf_printer_status_summary" AS
SELECT
  p."id" AS "printerId",
  p."name" AS "printerName",
  p."status" AS "wssStatus",
  p."operationalStatus",
  p."manualOverrideStatus",
  p."hasCompletedPrintOnBed",
  p."needsFilamentSwap",
  (
    SELECT COUNT(*)::INT
    FROM "print-farm"."PrinterIssue" i
    WHERE i."printerId" = p."id"
      AND i."status" = ANY (ARRAY['OPEN'::"print-farm"."PrinterIssueStatus", 'ACKED'::"print-farm"."PrinterIssueStatus"])
  ) AS "openIssuesCount",
  (
    SELECT r."finishedAt"
    FROM "print-farm"."PrintRun" r
    JOIN "print-farm"."PrinterAssignment" a ON a."id" = r."assignmentId"
    WHERE a."printerId" = p."id"
    ORDER BY r."finishedAt" DESC
    LIMIT 1
  ) AS "lastRunFinishedAt"
FROM "print-farm"."Printer" p
ORDER BY p."name";

COMMENT ON VIEW "print_farm_views"."v_pf_printer_status_summary" IS
  'Riepilogo stato per stampante con issue aperte e ultima run.';
