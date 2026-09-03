-- ============================================================================
-- Manodopera assemblaggio — Fase 2: tracciamento attività/heartbeat.
--
-- Cosa cambia:
--   * `AssemblyOperation` guadagna `lastActivityAt` e `lastHeartbeatAt`
--     (TIMESTAMPTZ, NULL di default): la chiusura idle-aware non deve più
--     rileggere il diario a ogni close; per le righe pre-Fase 2 (NULL) resta
--     il fallback journal/picking lato applicativo;
--   * indice (`endedAt`, `lastActivityAt`) per lo sweep cron delle sessioni
--     aperte/inattive;
--   * tre nuovi valori nell'enum `SettingsName` per le soglie idle
--     configurabili da `inventory."Settings"` (default applicativi invariati:
--     gap 45 min, cap 15 min, heartbeat 120 s).
--
-- Tutto additivo e idempotente: nessuna colonna esistente modificata,
-- nessun dato riscritto.
--
-- Applicabile anche via psql / Supabase SQL editor. Se lo fai fuori da Prisma:
--   bunx prisma migrate resolve --applied 20260904003000_assembly_operation_activity_tracking
-- ============================================================================

ALTER TABLE "inventory"."AssemblyOperation"
  ADD COLUMN IF NOT EXISTS "lastActivityAt" TIMESTAMPTZ(6),
  ADD COLUMN IF NOT EXISTS "lastHeartbeatAt" TIMESTAMPTZ(6);

CREATE INDEX IF NOT EXISTS "AssemblyOperation_endedAt_lastActivityAt_idx"
  ON "inventory"."AssemblyOperation"("endedAt", "lastActivityAt");

ALTER TYPE "inventory"."SettingsName" ADD VALUE IF NOT EXISTS 'ASSEMBLY_LABOR_IDLE_GAP_MINUTES';
ALTER TYPE "inventory"."SettingsName" ADD VALUE IF NOT EXISTS 'ASSEMBLY_LABOR_NO_ACTIVITY_CAP_MINUTES';
ALTER TYPE "inventory"."SettingsName" ADD VALUE IF NOT EXISTS 'ASSEMBLY_LABOR_HEARTBEAT_SECONDS';
