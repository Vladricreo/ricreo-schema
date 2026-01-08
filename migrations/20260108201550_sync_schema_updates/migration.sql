/*
  Warnings:

  - The values [TO_LOAD] on the enum `PrinterOperationalStatus` will be removed. If these variants are still used in the database, this will fail.

*/
-- Assicura che lo schema per le views esista (necessario per shadow DB)
CREATE SCHEMA IF NOT EXISTS "print_farm_views";

-- CupsPrintJobKind: enum per tipologie di job di stampa CUPS
-- Creato qui perché usato da CupsPrintProfile più sotto
CREATE TYPE "inventory"."CupsPrintJobKind" AS ENUM (
  'SHIPMENT_LABEL',
  'ITEM_LABEL',
  'ODETTE_LABEL',
  'PRODUCT_LABEL'
);

-- DropViews (dipendono da operationalStatus che stiamo per alterare)
DROP VIEW IF EXISTS "print_farm_views"."v_pf_printers_by_operational_status";
DROP VIEW IF EXISTS "print_farm_views"."v_pf_printer_status_summary";

-- AlterEnum (rimuove TO_LOAD, aggiunge PRINTING)
CREATE TYPE "print-farm"."PrinterOperationalStatus_new" AS ENUM ('AVAILABLE', 'QUEUED', 'PRINTING', 'NEEDS_SETUP', 'TO_HARVEST', 'FILAMENT_RUNOUT', 'FILAMENT_SWAP_NEEDED', 'ERROR');
ALTER TABLE "print-farm"."Printer" ALTER COLUMN "operationalStatus" DROP DEFAULT;
ALTER TABLE "print-farm"."Printer" ALTER COLUMN "operationalStatus" TYPE "print-farm"."PrinterOperationalStatus_new" USING ("operationalStatus"::text::"print-farm"."PrinterOperationalStatus_new");
ALTER TYPE "print-farm"."PrinterOperationalStatus" RENAME TO "PrinterOperationalStatus_old";
ALTER TYPE "print-farm"."PrinterOperationalStatus_new" RENAME TO "PrinterOperationalStatus";
DROP TYPE "print-farm"."PrinterOperationalStatus_old";
ALTER TABLE "print-farm"."Printer" ALTER COLUMN "operationalStatus" SET DEFAULT 'AVAILABLE';

-- RecreateViews
CREATE VIEW "print_farm_views"."v_pf_printers_by_operational_status" AS
SELECT "operationalStatus",
    count(*)::integer AS count
FROM "print-farm"."Printer" p
GROUP BY "operationalStatus"
ORDER BY (count(*)::integer) DESC;

CREATE VIEW "print_farm_views"."v_pf_printer_status_summary" AS
SELECT id AS "printerId",
    name AS "printerName",
    status AS "wssStatus",
    "operationalStatus",
    "manualOverrideStatus",
    "bedOccupied",
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

-- AlterTable
ALTER TABLE "print-farm"."PrinterAssignment" ADD COLUMN     "startPayload" JSONB;

-- CreateTable
CREATE TABLE "inventory"."CupsPrintProfile" (
    "id" UUID NOT NULL,
    "kind" "inventory"."CupsPrintJobKind" NOT NULL,
    "printerId" UUID,
    "labelFormatId" UUID,
    "jobOptions" JSONB NOT NULL DEFAULT '{}',
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CupsPrintProfile_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "CupsPrintProfile_printerId_idx" ON "inventory"."CupsPrintProfile"("printerId");

-- CreateIndex
CREATE INDEX "CupsPrintProfile_labelFormatId_idx" ON "inventory"."CupsPrintProfile"("labelFormatId");

-- CreateIndex
CREATE UNIQUE INDEX "CupsPrintProfile_kind_key" ON "inventory"."CupsPrintProfile"("kind");

-- AddForeignKey
ALTER TABLE "inventory"."CupsPrintProfile" ADD CONSTRAINT "CupsPrintProfile_printerId_fkey" FOREIGN KEY ("printerId") REFERENCES "inventory"."CupsPrinter"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."CupsPrintProfile" ADD CONSTRAINT "CupsPrintProfile_labelFormatId_fkey" FOREIGN KEY ("labelFormatId") REFERENCES "inventory"."CupsLabelFormat"("id") ON DELETE SET NULL ON UPDATE CASCADE;
