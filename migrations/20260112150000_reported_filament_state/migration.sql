-- Save "reported" filament info coming from printers (without spool tracking).
-- - AMS slots: stored on PrinterAmsSlot
-- - External spool: stored on Printer
--
-- These fields are intentionally separated from tracked spool relations (spoolId/currentSpoolId),
-- so the frontend can assign real virtual spools without being overwritten by telemetry.

-- AlterTable
ALTER TABLE "print-farm"."PrinterAmsSlot"
ADD COLUMN     "reportedMaterialType" TEXT,
ADD COLUMN     "reportedColor" TEXT,
ADD COLUMN     "reportedTrayInfoIdx" TEXT,
ADD COLUMN     "reportedLastSeenAt" TIMESTAMPTZ(6);

-- AlterTable
ALTER TABLE "print-farm"."Printer"
ADD COLUMN     "externalReportedMaterialType" TEXT,
ADD COLUMN     "externalReportedColor" TEXT,
ADD COLUMN     "externalReportedTrayInfoIdx" TEXT,
ADD COLUMN     "externalReportedLastSeenAt" TIMESTAMPTZ(6);

