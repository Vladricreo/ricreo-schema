-- ============================================================================
-- Rollout Gantt F8 (piano §15) — fix gate R15: denominatori corretti.
--
-- Cosa cambia (review R15, issues 2-3):
--   * `SchedulerRolloutMetric.sliceScopePrinters`: stampanti solver nello
--     scope della slice (canary, o tutta la flotta senza canary). Il fallback
--     rate del gate si calcola su questo denominatore, non sulla flotta
--     intera (`managedPrinters`): 2 rifiuti su 5 stampanti canary devono
--     leggere 40%, non 2/60.
--   * `SchedulerRolloutMetric.churnReplacedPrinters` /
--     `churnTrackedPrinters`: plan churn F8 vero — sostituzioni per stampante
--     rispetto alla SCHEDULED primaria precedente. I contatori apply
--     (created/updated/kept/cancelled) restano come contesto ma non sono
--     piu' la fonte del churn: fill da fermo e update payload-only non
--     contano come churn.
--
-- Tutto additivo e idempotente (IF NOT EXISTS): colonne nuove con default 0,
-- nessuna riga esistente riscritta, nessun impatto sulle altre app che
-- condividono il DB.
--
-- Applicabile anche via psql / Supabase SQL editor. Se lo fai fuori da Prisma:
--   bunx prisma migrate resolve --applied 20260924130000_rollout_metrics_gate_fixes
-- ============================================================================

ALTER TABLE "print-farm"."SchedulerRolloutMetric"
  ADD COLUMN IF NOT EXISTS "sliceScopePrinters" INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "churnReplacedPrinters" INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "churnTrackedPrinters" INTEGER NOT NULL DEFAULT 0;
