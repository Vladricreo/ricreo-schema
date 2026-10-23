-- Fotografia di capacità per giro di generate-assignments (dashboard
-- «Capacità e colli di bottiglia», 23/10). Solo diagnostica: lo scheduler
-- la scrive a fine giro e nessuna decisione la legge.

-- CreateTable
CREATE TABLE "print-farm"."SchedulerCapacitySnapshot" (
    "id" UUID NOT NULL,
    "version" INTEGER NOT NULL DEFAULT 1,
    "summary" JSONB NOT NULL,
    "detail" JSONB,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SchedulerCapacitySnapshot_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "SchedulerCapacitySnapshot_createdAt_idx" ON "print-farm"."SchedulerCapacitySnapshot"("createdAt");
