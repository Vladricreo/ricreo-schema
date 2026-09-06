-- Diario delle operazioni di assemblaggio ("AssemblyJournalEntry").
--
-- Perché: i `Movement` sono un registro piatto e non dicono che un certo gruppo di
-- movimenti, decrementi di odette e contatori era *una* operazione (un deposito, un
-- avanzamento, una chiusura SKU). Senza questo dato un revert può solo ricostruire
-- l'intenzione a naso: la rollback attuale, quando la UI non passa il dettaglio,
-- indovina le parti da restituire leggendo i movimenti USO delle ultime 2 ore, senza
-- filtro sull'ordine.
--
-- La entry viene scritta nella stessa transazione dell'operazione, quindi non può
-- divergere da quello che è stato realmente scritto.
--
-- Idempotente: enum con guard pg_type, tabella/colonne con IF NOT EXISTS, FK con
-- guard pg_constraint.

-- ─── 1) Enum AssemblyJournalKind ───────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type t
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'inventory'
      AND t.typname = 'AssemblyJournalKind'
  ) THEN
    CREATE TYPE "inventory"."AssemblyJournalKind" AS ENUM (
      'DEPOSIT',
      'ADVANCE',
      'SKU_COMPLETE',
      'SCRAP',
      'REVERT'
    );
  END IF;
END $$;

-- ─── 2) Enum AssemblyJournalStatus ─────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type t
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'inventory'
      AND t.typname = 'AssemblyJournalStatus'
  ) THEN
    CREATE TYPE "inventory"."AssemblyJournalStatus" AS ENUM (
      'APPLIED',
      'PARTIALLY_REVERTED',
      'REVERTED',
      'REVERT_ENTRY'
    );
  END IF;
END $$;

-- ─── 3) Tabella AssemblyJournalEntry ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS "inventory"."AssemblyJournalEntry" (
  "id"                 UUID           NOT NULL DEFAULT gen_random_uuid(),
  "assemblyOrderId"    UUID           NOT NULL,
  "kind"               "inventory"."AssemblyJournalKind"   NOT NULL,
  "status"             "inventory"."AssemblyJournalStatus" NOT NULL DEFAULT 'APPLIED',
  "fromStageType"      "inventory"."AssemblyStageType",
  "toStageType"        "inventory"."AssemblyStageType",
  "quantity"           INTEGER        NOT NULL DEFAULT 0,
  "quantityReverted"   INTEGER        NOT NULL DEFAULT 0,
  "orderVersionBefore" INTEGER,
  "orderVersionAfter"  INTEGER,
  "operatorId"         INTEGER,
  "revertsEntryId"     UUID,
  "payload"            JSONB          NOT NULL,
  "createdAt"          TIMESTAMPTZ(6) NOT NULL DEFAULT NOW(),
  "updatedAt"          TIMESTAMPTZ(6) NOT NULL DEFAULT NOW(),

  CONSTRAINT "AssemblyJournalEntry_pkey" PRIMARY KEY ("id")
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'AssemblyJournalEntry_assemblyOrderId_fkey'
  ) THEN
    ALTER TABLE "inventory"."AssemblyJournalEntry"
      ADD CONSTRAINT "AssemblyJournalEntry_assemblyOrderId_fkey"
      FOREIGN KEY ("assemblyOrderId") REFERENCES "inventory"."AssemblyOrder"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'AssemblyJournalEntry_operatorId_fkey'
  ) THEN
    ALTER TABLE "inventory"."AssemblyJournalEntry"
      ADD CONSTRAINT "AssemblyJournalEntry_operatorId_fkey"
      FOREIGN KEY ("operatorId") REFERENCES "public"."User"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'AssemblyJournalEntry_revertsEntryId_fkey'
  ) THEN
    ALTER TABLE "inventory"."AssemblyJournalEntry"
      ADD CONSTRAINT "AssemblyJournalEntry_revertsEntryId_fkey"
      FOREIGN KEY ("revertsEntryId") REFERENCES "inventory"."AssemblyJournalEntry"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS "AssemblyJournalEntry_assemblyOrderId_createdAt_idx"
  ON "inventory"."AssemblyJournalEntry"("assemblyOrderId", "createdAt");
CREATE INDEX IF NOT EXISTS "AssemblyJournalEntry_assemblyOrderId_status_idx"
  ON "inventory"."AssemblyJournalEntry"("assemblyOrderId", "status");
CREATE INDEX IF NOT EXISTS "AssemblyJournalEntry_revertsEntryId_idx"
  ON "inventory"."AssemblyJournalEntry"("revertsEntryId");
CREATE INDEX IF NOT EXISTS "AssemblyJournalEntry_operatorId_idx"
  ON "inventory"."AssemblyJournalEntry"("operatorId");

-- ─── 4) Movement.journalEntryId ────────────────────────────────────────────
-- Permette di raggruppare i movimenti per operazione nella pagina movimenti e di
-- revertare l'operazione agendo esattamente sui suoi movimenti.
ALTER TABLE "inventory"."Movement"
  ADD COLUMN IF NOT EXISTS "journalEntryId" UUID;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'Movement_journalEntryId_fkey'
  ) THEN
    ALTER TABLE "inventory"."Movement"
      ADD CONSTRAINT "Movement_journalEntryId_fkey"
      FOREIGN KEY ("journalEntryId") REFERENCES "inventory"."AssemblyJournalEntry"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS "Movement_journalEntryId_idx"
  ON "inventory"."Movement"("journalEntryId");
