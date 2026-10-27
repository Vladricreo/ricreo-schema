-- Ricarica prevista per gli slot in runout (S-183, 27/10).
-- La cron generate-assignments salva a ogni giro cosa propone la preparazione
-- per ricaricare uno slot in runout: bobina e dove si trova, oppure perché non
-- c'è (bobine della famiglia valutate con il motivo, buste). Solo indicazione:
-- nessun lock e nessuna relazione con AssignmentSpoolPlan.

-- CreateTable
CREATE TABLE "print-farm"."RunoutRechargePlan" (
    "id" UUID NOT NULL,
    "rowKey" TEXT NOT NULL,
    "printerId" UUID NOT NULL,
    "printerName" TEXT,
    "assignmentId" UUID,
    "slotLabel" TEXT,
    "targetItemId" UUID,
    "targetItemName" TEXT,
    "requiredGrams" DECIMAL(10,2),
    "spoolId" UUID,
    "tagCode" TEXT,
    "sourceKind" TEXT,
    "sourceLabel" TEXT,
    "proposedItemId" UUID,
    "proposedGrams" DECIMAL(10,2),
    "outOfStock" BOOLEAN NOT NULL DEFAULT false,
    "report" JSONB,
    "waitingFor" JSONB,
    "openedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "computedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "closedAt" TIMESTAMPTZ(6),

    CONSTRAINT "RunoutRechargePlan_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "RunoutRechargePlan_rowKey_closedAt_idx" ON "print-farm"."RunoutRechargePlan"("rowKey", "closedAt");

-- CreateIndex
CREATE INDEX "RunoutRechargePlan_printerId_openedAt_idx" ON "print-farm"."RunoutRechargePlan"("printerId", "openedAt");

-- CreateIndex
CREATE INDEX "RunoutRechargePlan_closedAt_idx" ON "print-farm"."RunoutRechargePlan"("closedAt");
