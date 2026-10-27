-- Piano asciugatura dello scheduler (R-109, 27/10): un record per ciclo
-- previsto (stampante + materiale), aggiornato a ogni piano Gantt e collegato
-- al ciclo vero e alla stampa, per vedere cosa è previsto, cosa è in ritardo
-- e cosa è stato fatto, e quando.

-- CreateEnum
CREATE TYPE "print-farm"."DryingPlanRecordStatus" AS ENUM ('PLANNED', 'LATE', 'DRYING', 'READY', 'CONSUMED', 'CANCELLED');

-- CreateTable
CREATE TABLE "print-farm"."DryingPlanRecord" (
    "id" UUID NOT NULL,
    "printerId" UUID NOT NULL,
    "amsId" INTEGER NOT NULL,
    "amsModel" TEXT NOT NULL,
    "materialKey" TEXT NOT NULL,
    "materialCategory" TEXT,
    "colorHex" TEXT,
    "spoolId" UUID,
    "status" "print-farm"."DryingPlanRecordStatus" NOT NULL DEFAULT 'PLANNED',
    "source" TEXT NOT NULL DEFAULT 'PLANNED',
    "tempC" INTEGER NOT NULL,
    "durationMinutes" INTEGER NOT NULL,
    "firstPlannedLoadAt" TIMESTAMPTZ(6),
    "firstPlannedStart" TIMESTAMPTZ(6) NOT NULL,
    "plannedLoadAt" TIMESTAMPTZ(6),
    "plannedStart" TIMESTAMPTZ(6) NOT NULL,
    "plannedEnd" TIMESTAMPTZ(6) NOT NULL,
    "readyAt" TIMESTAMPTZ(6) NOT NULL,
    "unlocksProductionJobId" UUID,
    "unlocksAt" TIMESTAMPTZ(6) NOT NULL,
    "replanCount" INTEGER NOT NULL DEFAULT 0,
    "lastGanttPlanId" UUID,
    "sessionId" UUID,
    "actualStartedAt" TIMESTAMPTZ(6),
    "actualCompletedAt" TIMESTAMPTZ(6),
    "consumedAt" TIMESTAMPTZ(6),
    "closedAt" TIMESTAMPTZ(6),
    "note" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "DryingPlanRecord_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "DryingPlanRecord_status_idx" ON "print-farm"."DryingPlanRecord"("status");

-- CreateIndex
CREATE INDEX "DryingPlanRecord_printerId_status_idx" ON "print-farm"."DryingPlanRecord"("printerId", "status");

-- CreateIndex
CREATE INDEX "DryingPlanRecord_createdAt_idx" ON "print-farm"."DryingPlanRecord"("createdAt");

-- Un solo record aperto per stampante e materiale: i piani successivi lo
-- aggiornano invece di crearne un altro (indice parziale, fuori da Prisma).
CREATE UNIQUE INDEX "DryingPlanRecord_open_per_printer_material"
  ON "print-farm"."DryingPlanRecord"("printerId", "materialKey")
  WHERE "status" IN ('PLANNED', 'LATE', 'DRYING', 'READY');

-- AddForeignKey
ALTER TABLE "print-farm"."DryingPlanRecord" ADD CONSTRAINT "DryingPlanRecord_printerId_fkey" FOREIGN KEY ("printerId") REFERENCES "print-farm"."Printer"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."DryingPlanRecord" ADD CONSTRAINT "DryingPlanRecord_spoolId_fkey" FOREIGN KEY ("spoolId") REFERENCES "print-farm"."FilamentSpool"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."DryingPlanRecord" ADD CONSTRAINT "DryingPlanRecord_sessionId_fkey" FOREIGN KEY ("sessionId") REFERENCES "print-farm"."SpoolDryingSession"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- RLS: tabella letta solo dalle app via Prisma (utente postgres).
ALTER TABLE "print-farm"."DryingPlanRecord" ENABLE ROW LEVEL SECURITY;
