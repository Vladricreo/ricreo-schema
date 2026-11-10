-- R-197 (10/11): congelamento della pianificazione per stampante, scelto in
-- Production («Congela», «Congela vista», cambio multiplo). Tabella nuova,
-- nessun dato esistente toccato. Finché la tabella manca il codice è
-- fail-open: nessun congelamento, il giro dello scheduler va avanti.

-- CreateTable
CREATE TABLE "print-farm"."PrinterPlanningFreeze" (
    "id" UUID NOT NULL,
    "printerId" UUID NOT NULL,
    "assignmentId" UUID,
    "productionJobId" UUID,
    "source" VARCHAR(20) NOT NULL,
    "frozenByUserId" INTEGER,
    "frozenByName" VARCHAR(120),
    "frozenAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expiresAt" TIMESTAMPTZ(6) NOT NULL,
    "releasedAt" TIMESTAMPTZ(6),
    "releaseReason" VARCHAR(20),
    "releasedByUserId" INTEGER,

    CONSTRAINT "PrinterPlanningFreeze_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "PrinterPlanningFreeze_releasedAt_printerId_idx" ON "print-farm"."PrinterPlanningFreeze"("releasedAt", "printerId");

-- CreateIndex
CREATE INDEX "PrinterPlanningFreeze_printerId_frozenAt_idx" ON "print-farm"."PrinterPlanningFreeze"("printerId", "frozenAt" DESC);

-- AddForeignKey
ALTER TABLE "print-farm"."PrinterPlanningFreeze" ADD CONSTRAINT "PrinterPlanningFreeze_printerId_fkey" FOREIGN KEY ("printerId") REFERENCES "print-farm"."Printer"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Letta e scritta solo via Prisma (postgres, proprietario): RLS senza policy chiude l'accesso anon.
ALTER TABLE "print-farm"."PrinterPlanningFreeze" ENABLE ROW LEVEL SECURITY;
