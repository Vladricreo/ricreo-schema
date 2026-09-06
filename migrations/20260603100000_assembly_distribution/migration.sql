-- Distribuzione automatica ordini di assemblaggio per operatore.
--
-- Aggiunge:
--   • "WorkShift": turno di lavoro settimanale ricorrente per utente
--   • "User"."assemblyInterventionOrder": ordine di intervento per la distribuzione
--   • "AssemblyOrder"."assignedToUserId": operatore pianificato (distinto da assembledByUserId)
--   • Enum SettingsName: nuovo valore ASSEMBLY_BASE_TIME_PER_PIECE
--
-- Idempotente: tutte le ALTER usano IF NOT EXISTS / guard pg_constraint / pg_enum.

-- ─── 1) User.assemblyInterventionOrder ─────────────────────────────────────
ALTER TABLE "public"."User"
  ADD COLUMN IF NOT EXISTS "assemblyInterventionOrder" SMALLINT;

COMMENT ON COLUMN "public"."User"."assemblyInterventionOrder"
  IS 'Ordine di intervento nella distribuzione automatica degli ordini di assemblaggio (minore = riempito prima). NULL = derivato dai ruoli RBAC.';

-- ─── 2) WorkShift ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "public"."WorkShift" (
  "id"          SERIAL      PRIMARY KEY,
  "userId"      INTEGER     NOT NULL,
  "dayOfWeek"   SMALLINT    NOT NULL,
  "startMinute" SMALLINT    NOT NULL,
  "endMinute"   SMALLINT    NOT NULL,
  "isActive"    BOOLEAN     NOT NULL DEFAULT TRUE,
  "createdAt"   TIMESTAMPTZ(6) NOT NULL DEFAULT NOW(),
  "updatedAt"   TIMESTAMPTZ(6) NOT NULL DEFAULT NOW()
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'WorkShift_userId_fkey'
  ) THEN
    ALTER TABLE "public"."WorkShift"
      ADD CONSTRAINT "WorkShift_userId_fkey"
      FOREIGN KEY ("userId") REFERENCES "public"."User"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS "WorkShift_userId_dayOfWeek_key"
  ON "public"."WorkShift"("userId", "dayOfWeek");
CREATE INDEX IF NOT EXISTS "WorkShift_userId_idx"
  ON "public"."WorkShift"("userId");
CREATE INDEX IF NOT EXISTS "WorkShift_dayOfWeek_idx"
  ON "public"."WorkShift"("dayOfWeek");

COMMENT ON TABLE "public"."WorkShift"
  IS 'Turno di lavoro settimanale ricorrente per utente (per la distribuzione assemblaggi).';
COMMENT ON COLUMN "public"."WorkShift"."dayOfWeek"
  IS 'Giorno della settimana: 0 = Domenica .. 6 = Sabato.';
COMMENT ON COLUMN "public"."WorkShift"."startMinute"
  IS 'Inizio turno in minuti dalla mezzanotte (es. 600 = 10:00).';
COMMENT ON COLUMN "public"."WorkShift"."endMinute"
  IS 'Fine turno in minuti dalla mezzanotte (es. 840 = 14:00). Deve essere > startMinute.';

-- ─── 3) AssemblyOrder.assignedToUserId ─────────────────────────────────────
ALTER TABLE "inventory"."AssemblyOrder"
  ADD COLUMN IF NOT EXISTS "assignedToUserId" INTEGER;

COMMENT ON COLUMN "inventory"."AssemblyOrder"."assignedToUserId"
  IS 'Operatore a cui è pianificato l''assemblaggio (distinto da assembledByUserId, che indica chi ha eseguito).';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'AssemblyOrder_assignedToUserId_fkey'
  ) THEN
    ALTER TABLE "inventory"."AssemblyOrder"
      ADD CONSTRAINT "AssemblyOrder_assignedToUserId_fkey"
      FOREIGN KEY ("assignedToUserId") REFERENCES "public"."User"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS "AssemblyOrder_assignedToUserId_idx"
  ON "inventory"."AssemblyOrder"("assignedToUserId");

-- ─── 4) Enum SettingsName: ASSEMBLY_BASE_TIME_PER_PIECE ────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'inventory'
      AND t.typname = 'SettingsName'
      AND e.enumlabel = 'ASSEMBLY_BASE_TIME_PER_PIECE'
  ) THEN
    ALTER TYPE "inventory"."SettingsName" ADD VALUE 'ASSEMBLY_BASE_TIME_PER_PIECE';
  END IF;
END $$;
