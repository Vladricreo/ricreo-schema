-- ============================================================================
-- ETA ordine F4.1 — quantile P95 e tier di rischio sulle previsioni.
-- (audit 2026-09-03: PIANO-AZIONE ondata 4, punto 4.1; piano §13 e §14.2;
--  finding SC13)
--
-- Cosa cambia:
--   * `ProductOrder.etaP95` (TIMESTAMPTZ, NULL): scenario avverso P95 dello
--     stesso modello Monte Carlo deterministico che produce `eta` (P50) e
--     `etaP80`. Popolato dal primo ciclo Gantt dopo il deploy.
--   * `SchedulerOrderEtaSnapshot.etaP95` (TIMESTAMPTZ, NULL): stesso quantile
--     sugli snapshot prospettici immutabili.
--   * `SchedulerOrderEtaSnapshot.riskTier` (TEXT, NULL): classificatore di
--     rischio del piano §13 — NORMALE (target oltre P95), A_RISCHIO (target
--     fra P80 e P95), CRITICO (fra P50 e P80), IN_RITARDO (prima di P50).
--     NULL onesto quando manca la dueDate o uno dei quantili: mai stimato.
--
-- Tutte le colonne sono NULL di default: il codice in produzione (vecchio)
-- continua a scrivere/leggere P50/P80 invariato; nessun dato esistente viene
-- riscritto. I tier restano derivabili anche dal breakdown JSON dello
-- snapshot (etaP95 + riskTier) per la diagnostica "perché questo ordine è a
-- rischio" (piano §14.2).
--
-- Tutto additivo e idempotente (IF NOT EXISTS).
--
-- Applicabile anche via psql / Supabase SQL editor. Se lo fai fuori da Prisma:
--   bunx prisma migrate resolve --applied 20260904023000_eta_p95_risk_tier
-- ============================================================================

ALTER TABLE "inventory"."ProductOrder"
  ADD COLUMN IF NOT EXISTS "etaP95" TIMESTAMPTZ(6);

ALTER TABLE "print-farm"."SchedulerOrderEtaSnapshot"
  ADD COLUMN IF NOT EXISTS "etaP95" TIMESTAMPTZ(6),
  ADD COLUMN IF NOT EXISTS "riskTier" TEXT;
