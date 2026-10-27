-- Cicli di asciugatura nel piano Gantt (fase 3 di R-104, 27/10).
-- Il ciclo occupa un'unità AMS che asciuga (AMS HT o 2 Pro), non la
-- stampante: sta in una tabella sua così capacità, ETA e lock, che leggono
-- GanttTask come tempo macchina, non lo contano. Solo diagnostica e guida
-- operatore: nessuna decisione di assignment lo legge.

-- CreateTable
CREATE TABLE "print-farm"."GanttDryingTask" (
    "id" UUID NOT NULL,
    "ganttPlanId" UUID NOT NULL,
    "printerId" UUID NOT NULL,
    "amsId" INTEGER NOT NULL,
    "amsModel" TEXT NOT NULL,
    "materialKey" TEXT NOT NULL,
    "materialCategory" TEXT,
    "colorHex" TEXT,
    "tempC" INTEGER NOT NULL,
    "durationMinutes" INTEGER NOT NULL,
    "loadStart" TIMESTAMPTZ(6),
    "plannedStart" TIMESTAMPTZ(6) NOT NULL,
    "plannedEnd" TIMESTAMPTZ(6) NOT NULL,
    "readyAt" TIMESTAMPTZ(6) NOT NULL,
    "source" TEXT NOT NULL DEFAULT 'PLANNED',
    "unlocksProductionJobId" UUID,
    "unlocksAt" TIMESTAMPTZ(6) NOT NULL,
    "conflictNote" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "GanttDryingTask_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "GanttDryingTask_ganttPlanId_idx" ON "print-farm"."GanttDryingTask"("ganttPlanId");

-- CreateIndex
CREATE INDEX "GanttDryingTask_printerId_plannedStart_idx" ON "print-farm"."GanttDryingTask"("printerId", "plannedStart");

-- AddForeignKey
ALTER TABLE "print-farm"."GanttDryingTask" ADD CONSTRAINT "GanttDryingTask_ganttPlanId_fkey" FOREIGN KEY ("ganttPlanId") REFERENCES "print-farm"."GanttPlan"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."GanttDryingTask" ADD CONSTRAINT "GanttDryingTask_printerId_fkey" FOREIGN KEY ("printerId") REFERENCES "print-farm"."Printer"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- RLS: tabella letta solo dalle app via Prisma (utente postgres).
ALTER TABLE "print-farm"."GanttDryingTask" ENABLE ROW LEVEL SECURITY;
