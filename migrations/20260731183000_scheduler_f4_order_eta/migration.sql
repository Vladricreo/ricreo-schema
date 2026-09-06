-- F4: ETA ordine P50/P80 dal piano Gantt e snapshot prospettici di accuratezza.
ALTER TABLE "inventory"."ProductOrder"
  ADD COLUMN "etaP80" TIMESTAMPTZ(6),
  ADD COLUMN "etaConfidence" DOUBLE PRECISION,
  ADD COLUMN "etaBreakdown" JSONB;

ALTER TABLE "print-farm"."SchedulerCalibration"
  ADD COLUMN "durationVariance" DECIMAL(12,8) NOT NULL DEFAULT 0;

CREATE TABLE "print-farm"."SchedulerOrderEtaSnapshot" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "ganttPlanId" UUID NOT NULL,
  "productOrderId" UUID NOT NULL,
  "forecastAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "etaP50" TIMESTAMPTZ(6) NOT NULL,
  "etaP80" TIMESTAMPTZ(6) NOT NULL,
  "confidence" DOUBLE PRECISION NOT NULL,
  "source" TEXT NOT NULL,
  "coverage" DOUBLE PRECISION NOT NULL,
  "breakdown" JSONB NOT NULL,
  CONSTRAINT "SchedulerOrderEtaSnapshot_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "SchedulerOrderEtaSnapshot_ganttPlanId_productOrderId_key"
  ON "print-farm"."SchedulerOrderEtaSnapshot"("ganttPlanId", "productOrderId");
CREATE INDEX "SchedulerOrderEtaSnapshot_productOrderId_forecastAt_idx"
  ON "print-farm"."SchedulerOrderEtaSnapshot"("productOrderId", "forecastAt");
CREATE INDEX "SchedulerOrderEtaSnapshot_forecastAt_idx"
  ON "print-farm"."SchedulerOrderEtaSnapshot"("forecastAt");

ALTER TABLE "print-farm"."SchedulerOrderEtaSnapshot"
  ADD CONSTRAINT "SchedulerOrderEtaSnapshot_ganttPlanId_fkey"
  FOREIGN KEY ("ganttPlanId")
  REFERENCES "print-farm"."GanttPlan"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "print-farm"."SchedulerOrderEtaSnapshot"
  ADD CONSTRAINT "SchedulerOrderEtaSnapshot_productOrderId_fkey"
  FOREIGN KEY ("productOrderId")
  REFERENCES "inventory"."ProductOrder"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
