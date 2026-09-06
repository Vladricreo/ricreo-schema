-- ============================================================================
-- Motore di copertura F2 — superficie data sull'ordine di produzione.
-- (audit 2026-09-03: PIANO-AZIONE ondata 3, punto 3.1; piano §4.2, §5, §6)
--
-- Cosa cambia:
--   * `ProductOrder.dueDateOrigin` (enum, NULL): provenienza della data di
--     scadenza — COVERAGE (calcolata dal motore di copertura), KIT (derivata
--     da uno slot di assemblaggio), MANUAL (decisa dall'utente). Senza
--     provenienza una data scritta a mano e una calcolata sarebbero
--     indistinguibili (piano §14.2).
--   * `ProductOrder.lane` (enum, NULL): corsia operativa dell'ordine —
--     COMPLETAMENTO_KIT / COPERTURA_FBM / REINTEGRO_FBA / MANUALE
--     (modello a corsie, piano §5). Nullable finché F3 non assegna le corsie.
--
-- Entrambe le colonne sono NULL di default: il codice in produzione (vecchio)
-- continua a funzionare invariato; nessun dato esistente viene riscritto.
-- `dueDate` resta nullable per scelta (§4.1: niente SLA inventati).
--
-- Tutto additivo e idempotente (IF NOT EXISTS / duplicate_object tollerato).
--
-- Applicabile anche via psql / Supabase SQL editor. Se lo fai fuori da Prisma:
--   bunx prisma migrate resolve --applied 20260904013000_coverage_order_fields
-- ============================================================================

-- Enum separati per schema "inventory" (convenzione del submodule condiviso).
DO $$ BEGIN
  CREATE TYPE "inventory"."ProductOrderDueDateOrigin" AS ENUM ('COVERAGE', 'KIT', 'MANUAL');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "inventory"."ProductOrderLane" AS ENUM ('COMPLETAMENTO_KIT', 'COPERTURA_FBM', 'REINTEGRO_FBA', 'MANUALE');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE "inventory"."ProductOrder"
  ADD COLUMN IF NOT EXISTS "dueDateOrigin" "inventory"."ProductOrderDueDateOrigin",
  ADD COLUMN IF NOT EXISTS "lane" "inventory"."ProductOrderLane";

-- Il report di copertura e lo scheduler leggono/filtrano per corsia e data.
CREATE INDEX IF NOT EXISTS "ProductOrder_lane_idx"
  ON "inventory"."ProductOrder"("lane");
