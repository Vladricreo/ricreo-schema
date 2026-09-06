-- Alias di compatibilità per il codice già deployato (Prisma + SQL raw)
-- che fa ancora CAST a "print-farm"."QueueTaskStatus" ecc.
-- Le colonne restano sui tipi public.snake_case (wal2json/Realtime OK).

CREATE DOMAIN "print-farm"."PrinterBrand" AS public.printer_brand;
CREATE DOMAIN "print-farm"."SoftwareType" AS public.software_type;
CREATE DOMAIN "print-farm"."PrinterStatus" AS public.printer_status;
CREATE DOMAIN "print-farm"."PrinterOperationalStatus" AS public.printer_operational_status;
CREATE DOMAIN "print-farm"."PrinterManualOverrideStatus" AS public.printer_manual_override_status;
CREATE DOMAIN "print-farm"."AmsModel" AS public.ams_model;
CREATE DOMAIN "print-farm"."PlateType" AS public.plate_type;
CREATE DOMAIN "print-farm"."AssignmentStatus" AS public.assignment_status;
CREATE DOMAIN "print-farm"."QueueTaskStatus" AS public.queue_task_status;
