-- F3: persiste diagnostica/churn/copertura e livello capacitivo giorni 4-7.
ALTER TABLE "print-farm"."GanttPlan"
ADD COLUMN "diagnostics" JSONB,
ADD COLUMN "capacityPlan" JSONB;
