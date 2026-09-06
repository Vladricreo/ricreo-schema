-- Passaggi operativi dei task di miglioramento, con incaricati in sequenza.

CREATE TYPE "product"."ImprovementTaskStepStatus" AS ENUM ('PENDING', 'ACTIVE', 'COMPLETED');

CREATE TABLE "product"."ImprovementTaskStep" (
    "id" TEXT NOT NULL,
    "taskId" TEXT NOT NULL,
    "sortOrder" INTEGER NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT NOT NULL DEFAULT '',
    "status" "product"."ImprovementTaskStepStatus" NOT NULL DEFAULT 'PENDING',
    "completedAt" TIMESTAMPTZ(6),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "ImprovementTaskStep_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "product"."ImprovementTaskStepAssignee" (
    "id" TEXT NOT NULL,
    "stepId" TEXT NOT NULL,
    "userId" INTEGER NOT NULL,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "completedAt" TIMESTAMPTZ(6),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ImprovementTaskStepAssignee_pkey" PRIMARY KEY ("id")
);

ALTER TABLE "product"."ImprovementTaskStep"
    ADD CONSTRAINT "ImprovementTaskStep_taskId_fkey"
    FOREIGN KEY ("taskId") REFERENCES "product"."ImprovementTask"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "product"."ImprovementTaskStepAssignee"
    ADD CONSTRAINT "ImprovementTaskStepAssignee_stepId_fkey"
    FOREIGN KEY ("stepId") REFERENCES "product"."ImprovementTaskStep"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;

CREATE INDEX "ImprovementTaskStep_taskId_sortOrder_idx"
    ON "product"."ImprovementTaskStep"("taskId", "sortOrder");

CREATE UNIQUE INDEX "ImprovementTaskStepAssignee_stepId_userId_key"
    ON "product"."ImprovementTaskStepAssignee"("stepId", "userId");

CREATE INDEX "ImprovementTaskStepAssignee_userId_idx"
    ON "product"."ImprovementTaskStepAssignee"("userId");

CREATE INDEX "ImprovementTaskStepAssignee_stepId_sortOrder_idx"
    ON "product"."ImprovementTaskStepAssignee"("stepId", "sortOrder");
