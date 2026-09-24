-- ============================================================================
-- Rollout Gantt F8 (piano §15) — tabella metriche per-generazione.
--
-- Cosa cambia:
--   * Nuova tabella `print-farm`.`SchedulerRolloutMetric`: una riga per ciclo
--     di assegnazioni persistito con le metriche del gate di promozione
--     Gantt autorevole — agreement legacy↔Gantt, churn del piano applicato,
--     fallback anomali, esclusioni canary e tempi solver.
--   * Relazione opzionale verso `GanttPlan` (piano di riferimento al momento
--     della misura), ON DELETE SET NULL: lo storico metriche sopravvive alla
--     rotazione dei piani.
--
-- La tabella è append-only: nessuna riga esistente viene aggiornata dai
-- consumer (lib/scheduler/gantt-rollout-metrics.ts). Lettura unica dal gate
-- `evaluateGanttRolloutGate` e dalla route GET /api/scheduler/rollout-gate.
--
-- Tutto additivo e idempotente (IF NOT EXISTS): nessuna tabella, vista o
-- colonna esistente viene toccata; nessun impatto sulle altre app che
-- condividono il DB (Inventory non legge questa tabella).
--
-- Applicabile anche via psql / Supabase SQL editor. Se lo fai fuori da Prisma:
--   bunx prisma migrate resolve --applied 20260924120000_gantt_rollout_metrics
-- ============================================================================

CREATE TABLE IF NOT EXISTS "print-farm"."SchedulerRolloutMetric" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "sourcePolicy" TEXT NOT NULL,
  "correlationId" TEXT,
  "ganttPlanId" UUID,
  "comparedPrinters" INTEGER NOT NULL DEFAULT 0,
  "agreements" INTEGER NOT NULL DEFAULT 0,
  "divergences" INTEGER NOT NULL DEFAULT 0,
  "agreementRatio" DECIMAL(7,6),
  "assignmentsCreated" INTEGER NOT NULL DEFAULT 0,
  "assignmentsUpdated" INTEGER NOT NULL DEFAULT 0,
  "assignmentsKept" INTEGER NOT NULL DEFAULT 0,
  "assignmentsCancelled" INTEGER NOT NULL DEFAULT 0,
  "churnRatio" DECIMAL(7,6),
  "managedPrinters" INTEGER NOT NULL DEFAULT 0,
  "fallbackCount" INTEGER NOT NULL DEFAULT 0,
  "rejectedCount" INTEGER NOT NULL DEFAULT 0,
  "canaryExcludedCount" INTEGER NOT NULL DEFAULT 0,
  "stalePlanReason" TEXT,
  "generationDurationMs" INTEGER,
  "ganttSolverDurationMs" INTEGER,
  "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "SchedulerRolloutMetric_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "SchedulerRolloutMetric_createdAt_idx"
  ON "print-farm"."SchedulerRolloutMetric"("createdAt");
CREATE INDEX IF NOT EXISTS "SchedulerRolloutMetric_sourcePolicy_createdAt_idx"
  ON "print-farm"."SchedulerRolloutMetric"("sourcePolicy", "createdAt");
CREATE INDEX IF NOT EXISTS "SchedulerRolloutMetric_ganttPlanId_idx"
  ON "print-farm"."SchedulerRolloutMetric"("ganttPlanId");

DO $$ BEGIN
  ALTER TABLE "print-farm"."SchedulerRolloutMetric"
    ADD CONSTRAINT "SchedulerRolloutMetric_ganttPlanId_fkey"
    FOREIGN KEY ("ganttPlanId")
    REFERENCES "print-farm"."GanttPlan"("id")
    ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
