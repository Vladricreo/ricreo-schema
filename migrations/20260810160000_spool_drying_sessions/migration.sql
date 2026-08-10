-- Asciugatura tracciata a livello di bobina fisica (AMS HT), indipendente dagli assignment.

-- 1) Stati e origine del ciclo.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_type t
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE t.typname = 'SpoolDryingSessionStatus' AND n.nspname = 'print-farm'
  ) THEN
    CREATE TYPE "print-farm"."SpoolDryingSessionStatus" AS ENUM (
      'DRYING', 'COMPLETED', 'STOPPED', 'FAILED'
    );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_type t
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE t.typname = 'SpoolDryingTrigger' AND n.nspname = 'print-farm'
  ) THEN
    CREATE TYPE "print-farm"."SpoolDryingTrigger" AS ENUM ('MANUAL', 'PRINT_START');
  END IF;
END $$;

-- 2) Sessione di asciugatura bobina.
CREATE TABLE IF NOT EXISTS "print-farm"."SpoolDryingSession" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "spoolId" UUID NOT NULL,
    "printerId" UUID NOT NULL,
    "amsUnitId" UUID NOT NULL,
    "amsSlotId" UUID NOT NULL,
    "status" "print-farm"."SpoolDryingSessionStatus" NOT NULL DEFAULT 'DRYING',
    "trigger" "print-farm"."SpoolDryingTrigger" NOT NULL DEFAULT 'MANUAL',
    "tempC" INTEGER NOT NULL,
    "durationMinutes" INTEGER NOT NULL,
    "freshnessHours" INTEGER NOT NULL,
    "filamentLabel" TEXT,
    "startedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expectedEndAt" TIMESTAMPTZ(6) NOT NULL,
    "completedAt" TIMESTAMPTZ(6),
    "stoppedAt" TIMESTAMPTZ(6),
    "freshnessUntil" TIMESTAMPTZ(6),
    "commandIdempotencyKey" TEXT NOT NULL,
    "failureReason" TEXT,
    "operatorUserId" INTEGER,
    "metadata" JSONB,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "SpoolDryingSession_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "SpoolDryingSession_commandIdempotencyKey_key"
    ON "print-farm"."SpoolDryingSession"("commandIdempotencyKey");
CREATE INDEX IF NOT EXISTS "SpoolDryingSession_spoolId_startedAt_idx"
    ON "print-farm"."SpoolDryingSession"("spoolId", "startedAt" DESC);
CREATE INDEX IF NOT EXISTS "SpoolDryingSession_printerId_status_idx"
    ON "print-farm"."SpoolDryingSession"("printerId", "status");
CREATE INDEX IF NOT EXISTS "SpoolDryingSession_amsUnitId_status_idx"
    ON "print-farm"."SpoolDryingSession"("amsUnitId", "status");
CREATE INDEX IF NOT EXISTS "SpoolDryingSession_status_startedAt_idx"
    ON "print-farm"."SpoolDryingSession"("status", "startedAt" DESC);

-- Un solo ciclo attivo per unita' AMS e per bobina: l'unita' che asciuga e'
-- occupata in esclusiva, e la stessa bobina non puo' essere in due cicli.
CREATE UNIQUE INDEX IF NOT EXISTS "SpoolDryingSession_activeUnit_key"
    ON "print-farm"."SpoolDryingSession"("amsUnitId")
    WHERE "status" = 'DRYING';
CREATE UNIQUE INDEX IF NOT EXISTS "SpoolDryingSession_activeSpool_key"
    ON "print-farm"."SpoolDryingSession"("spoolId")
    WHERE "status" = 'DRYING';

ALTER TABLE "print-farm"."SpoolDryingSession"
    DROP CONSTRAINT IF EXISTS "SpoolDryingSession_spoolId_fkey";
ALTER TABLE "print-farm"."SpoolDryingSession"
    ADD CONSTRAINT "SpoolDryingSession_spoolId_fkey"
    FOREIGN KEY ("spoolId") REFERENCES "print-farm"."FilamentSpool"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "print-farm"."SpoolDryingSession"
    DROP CONSTRAINT IF EXISTS "SpoolDryingSession_printerId_fkey";
ALTER TABLE "print-farm"."SpoolDryingSession"
    ADD CONSTRAINT "SpoolDryingSession_printerId_fkey"
    FOREIGN KEY ("printerId") REFERENCES "print-farm"."Printer"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "print-farm"."SpoolDryingSession"
    DROP CONSTRAINT IF EXISTS "SpoolDryingSession_amsUnitId_fkey";
ALTER TABLE "print-farm"."SpoolDryingSession"
    ADD CONSTRAINT "SpoolDryingSession_amsUnitId_fkey"
    FOREIGN KEY ("amsUnitId") REFERENCES "print-farm"."PrinterAmsUnit"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "print-farm"."SpoolDryingSession"
    DROP CONSTRAINT IF EXISTS "SpoolDryingSession_amsSlotId_fkey";
ALTER TABLE "print-farm"."SpoolDryingSession"
    ADD CONSTRAINT "SpoolDryingSession_amsSlotId_fkey"
    FOREIGN KEY ("amsSlotId") REFERENCES "print-farm"."PrinterAmsSlot"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;

-- 3) Una bobina sigillata appena aperta e' asciutta: l'apertura vale come
-- ultima asciugatura, da cui parte la finestra di validita' del materiale.
ALTER TABLE "print-farm"."FilamentSpool"
  ALTER COLUMN "lastDriedAt" SET DEFAULT CURRENT_TIMESTAMP;

-- Backfill delle bobine gia' aperte senza alcuna asciugatura registrata.
-- Le aperture vecchie restano "scadute", perche' la validita' e' relativa.
UPDATE "print-farm"."FilamentSpool"
SET "lastDriedAt" = "openedAt"
WHERE "lastDriedAt" IS NULL;
