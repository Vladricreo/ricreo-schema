-- Estensioni alla distribuzione assemblaggi:
--   • "Role": flag di configurazione assemblaggio (impiego, priorità, gestione assegnazioni)
--   • "WorkShift"."cost": costo del turno
--   • "AssemblyOrder"."assignmentIsManual": assegnazione manuale (non toccata dalla distribuzione)
--
-- Idempotente: ADD COLUMN IF NOT EXISTS + UPDATE per i default sensati sui ruoli noti.

-- ─── 1) Role: configurazione assemblaggio ──────────────────────────────────
ALTER TABLE "public"."Role"
  ADD COLUMN IF NOT EXISTS "isAssemblyRole" BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS "assemblyPriority" SMALLINT,
  ADD COLUMN IF NOT EXISTS "canManageAssemblyAssignments" BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN "public"."Role"."isAssemblyRole"
  IS 'Se true, gli utenti con questo ruolo sono impiegati nell''assemblaggio (distribuzione automatica).';
COMMENT ON COLUMN "public"."Role"."assemblyPriority"
  IS 'Priorità di intervento del ruolo nella distribuzione (minore = riempito prima).';
COMMENT ON COLUMN "public"."Role"."canManageAssemblyAssignments"
  IS 'Se true, gli utenti con questo ruolo possono modificare le assegnazioni degli ordini di assemblaggio.';

-- Default sensati per i ruoli noti (solo se presenti).
UPDATE "public"."Role"
  SET "isAssemblyRole" = TRUE, "assemblyPriority" = 0
  WHERE "name" = 'Assemblatore';
UPDATE "public"."Role"
  SET "isAssemblyRole" = TRUE, "assemblyPriority" = 1
  WHERE "name" = 'GestoreStampanti';
UPDATE "public"."Role"
  SET "canManageAssemblyAssignments" = TRUE
  WHERE "name" IN ('Admin', 'Manager');

-- ─── 2) WorkShift.cost ─────────────────────────────────────────────────────
ALTER TABLE "public"."WorkShift"
  ADD COLUMN IF NOT EXISTS "cost" DECIMAL(12, 2);

COMMENT ON COLUMN "public"."WorkShift"."cost"
  IS 'Costo del turno (es. costo manodopera per la durata del turno). Opzionale.';

-- ─── 3) AssemblyOrder.assignmentIsManual ───────────────────────────────────
ALTER TABLE "inventory"."AssemblyOrder"
  ADD COLUMN IF NOT EXISTS "assignmentIsManual" BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN "inventory"."AssemblyOrder"."assignmentIsManual"
  IS 'Se true, l''assegnazione è manuale e non verrà modificata dalla distribuzione automatica.';
