-- Pianificazione manutenzioni (ISO 9001/14224): nuovo modello PrinterMaintenancePlan
-- + estensione di PrinterMaintenanceLog con campi di pianificazione/esito/verifica.
-- Idempotente: sicuro da rieseguire (es. dopo prisma db push o doppio deploy).

-- ─── Enum: MaintenanceRecurrenceMode ─────────────────────────────────────────
DO $$
BEGIN
  CREATE TYPE "print-farm"."MaintenanceRecurrenceMode" AS ENUM (
    'NONE', 'DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- ─── Enum: MaintenanceOutcome ────────────────────────────────────────────────
DO $$
BEGIN
  CREATE TYPE "print-farm"."MaintenanceOutcome" AS ENUM (
    'OK', 'OK_WITH_NOTES', 'NOT_RESOLVED', 'POSTPONED'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- ─── Tabella: PrinterMaintenancePlan ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "print-farm"."PrinterMaintenancePlan" (
  "id"                    UUID NOT NULL DEFAULT gen_random_uuid(),
  "number"                BIGSERIAL NOT NULL,
  "printerId"             UUID NOT NULL,
  "type"                  "print-farm"."MaintenanceType" NOT NULL DEFAULT 'ORDINARY',
  "title"                 TEXT NOT NULL,
  "description"           TEXT,
  "checklistTemplate"     JSONB,
  "estimatedDurationMin"  INTEGER,
  "suggestedParts"        JSONB,
  "recurrenceMode"        "print-farm"."MaintenanceRecurrenceMode" NOT NULL DEFAULT 'NONE',
  "intervalValue"         INTEGER,
  "graceDays"             INTEGER DEFAULT 7,
  "anchorDate"            TIMESTAMPTZ(6),
  "nextDueAt"             TIMESTAMPTZ(6),
  "lastTriggeredAt"       TIMESTAMPTZ(6),
  "remindBeforeDays"      INTEGER NOT NULL DEFAULT 3,
  "active"                BOOLEAN NOT NULL DEFAULT TRUE,
  "createdAt"             TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt"             TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdBy"             TEXT,
  "updatedBy"             TEXT,
  CONSTRAINT "PrinterMaintenancePlan_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "PrinterMaintenancePlan_number_key" UNIQUE ("number")
);

-- FK printer → cascade su delete (se la stampante sparisce, sparisce il piano).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'PrinterMaintenancePlan_printerId_fkey'
  ) THEN
    ALTER TABLE "print-farm"."PrinterMaintenancePlan"
      ADD CONSTRAINT "PrinterMaintenancePlan_printerId_fkey"
      FOREIGN KEY ("printerId") REFERENCES "print-farm"."Printer"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS "PrinterMaintenancePlan_printerId_active_idx"
  ON "print-farm"."PrinterMaintenancePlan" ("printerId", "active");

CREATE INDEX IF NOT EXISTS "PrinterMaintenancePlan_nextDueAt_idx"
  ON "print-farm"."PrinterMaintenancePlan" ("nextDueAt");

-- ─── Estensione PrinterMaintenanceLog (campi pianificazione + ISO) ───────────
ALTER TABLE "print-farm"."PrinterMaintenanceLog"
  ADD COLUMN IF NOT EXISTS "scheduledFor" TIMESTAMPTZ(6),
  ADD COLUMN IF NOT EXISTS "planId"       UUID,
  ADD COLUMN IF NOT EXISTS "checklist"    JSONB,
  ADD COLUMN IF NOT EXISTS "outcome"      "print-farm"."MaintenanceOutcome",
  ADD COLUMN IF NOT EXISTS "outcomeNotes" TEXT,
  ADD COLUMN IF NOT EXISTS "verifiedBy"   TEXT,
  ADD COLUMN IF NOT EXISTS "verifiedAt"   TIMESTAMPTZ(6);

-- FK log → plan (SetNull: se il piano viene cancellato, lo storico log resta orfano ma valido).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'PrinterMaintenanceLog_planId_fkey'
  ) THEN
    ALTER TABLE "print-farm"."PrinterMaintenanceLog"
      ADD CONSTRAINT "PrinterMaintenanceLog_planId_fkey"
      FOREIGN KEY ("planId") REFERENCES "print-farm"."PrinterMaintenancePlan"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS "PrinterMaintenanceLog_printerId_scheduledFor_idx"
  ON "print-farm"."PrinterMaintenanceLog" ("printerId", "scheduledFor");

CREATE INDEX IF NOT EXISTS "PrinterMaintenanceLog_status_scheduledFor_idx"
  ON "print-farm"."PrinterMaintenanceLog" ("status", "scheduledFor");

CREATE INDEX IF NOT EXISTS "PrinterMaintenanceLog_planId_idx"
  ON "print-farm"."PrinterMaintenanceLog" ("planId");
