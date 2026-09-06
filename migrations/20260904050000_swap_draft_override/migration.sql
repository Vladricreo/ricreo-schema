-- ============================================================================
-- Override operatore sulla bozza swap/runout (W-OVERRIDE, review R11).
--
-- Cosa cambia:
--   * "print-farm"."SpoolSwapDraft"."override" (JSONB, NULL): registrazione
--     first-class della scelta manuale della bobina A nel picker preparazione.
--     Payload: { "override": true, "reason"?, "fromSuggestedSpoolId",
--     "toSpoolId", "brandBreak", "partialCoverage" }.
--
-- Semantica:
--   * NULL = la bozza riflette il piano senza scelta manuale (default: il
--     codice in produzione continua a leggere/scrivere le altre colonne
--     invariato; nessun dato esistente viene riscritto).
--   * La colonna è solo il trasporto bozza → voce/TV: la registrazione
--     durevole dell'override resta nei metadata del SchedulerInterventionLog
--     (eventi swap-session:<id> e filament-load:<id>).
--
-- Additivo e idempotente (IF NOT EXISTS).
--
-- Applicabile anche via psql / Supabase SQL editor. Se lo fai fuori da Prisma:
--   bunx prisma migrate resolve --applied 20260904050000_swap_draft_override
-- ============================================================================

ALTER TABLE "print-farm"."SpoolSwapDraft"
  ADD COLUMN IF NOT EXISTS "override" JSONB;
