-- F6/WP7: audit e idempotenza delle assignment derivate dalla prima slice Gantt.
-- Ripara eventuali duplicati storici prima di imporre l'invariante globale.
WITH "rankedActivePlans" AS (
  SELECT
    "id",
    ROW_NUMBER() OVER (
      ORDER BY "updatedAt" DESC, "createdAt" DESC, "id" DESC
    ) AS "activeRank"
  FROM "print-farm"."GanttPlan"
  WHERE "status" = 'ACTIVE'
)
UPDATE "print-farm"."GanttPlan" AS "plan"
SET
  "status" = 'SUPERSEDED',
  "updatedAt" = CURRENT_TIMESTAMP
FROM "rankedActivePlans" AS "ranked"
WHERE "plan"."id" = "ranked"."id"
  AND "ranked"."activeRank" > 1;

-- Anche route manuali e processi concorrenti possono generare un piano:
-- il DB resta l'ultima barriera contro due Gantt ACTIVE simultanei.
CREATE UNIQUE INDEX "GanttPlan_single_active_idx"
  ON "print-farm"."GanttPlan"("status")
  WHERE "status" = 'ACTIVE';

ALTER TABLE "print-farm"."PrinterAssignment"
  ADD COLUMN "sourceGanttPlanId" UUID,
  ADD COLUMN "sourceGanttTaskId" UUID;

CREATE UNIQUE INDEX "PrinterAssignment_sourceGanttTaskId_key"
  ON "print-farm"."PrinterAssignment"("sourceGanttTaskId");

CREATE INDEX "PrinterAssignment_sourceGanttPlanId_idx"
  ON "print-farm"."PrinterAssignment"("sourceGanttPlanId");

ALTER TABLE "print-farm"."PrinterAssignment"
  ADD CONSTRAINT "PrinterAssignment_sourceGanttPlanId_fkey"
  FOREIGN KEY ("sourceGanttPlanId")
  REFERENCES "print-farm"."GanttPlan"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "print-farm"."PrinterAssignment"
  ADD CONSTRAINT "PrinterAssignment_sourceGanttTaskId_fkey"
  FOREIGN KEY ("sourceGanttTaskId")
  REFERENCES "print-farm"."GanttTask"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;
