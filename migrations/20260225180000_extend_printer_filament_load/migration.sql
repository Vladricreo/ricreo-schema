-- Enum per il trigger di caricamento filamento
DO $$ BEGIN
  CREATE TYPE "print-farm"."FilamentLoadTrigger" AS ENUM ('MANUAL', 'RUNOUT', 'SWAP', 'MISMATCH');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Nuovi campi su PrinterFilamentLoad
ALTER TABLE "print-farm"."PrinterFilamentLoad"
  ADD COLUMN IF NOT EXISTS "trigger" "print-farm"."FilamentLoadTrigger" NOT NULL DEFAULT 'MANUAL',
  ADD COLUMN IF NOT EXISTS "targetKind" VARCHAR(10) NOT NULL DEFAULT 'external',
  ADD COLUMN IF NOT EXISTS "amsUnit" INTEGER,
  ADD COLUMN IF NOT EXISTS "slot" INTEGER,
  ADD COLUMN IF NOT EXISTS "previousColor" TEXT,
  ADD COLUMN IF NOT EXISTS "oldSpoolId" UUID,
  ADD COLUMN IF NOT EXISTS "oldSpoolAction" VARCHAR(20),
  ADD COLUMN IF NOT EXISTS "movementId" UUID,
  ADD COLUMN IF NOT EXISTS "itemId" UUID,
  ADD COLUMN IF NOT EXISTS "undone" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "undoneAt" TIMESTAMPTZ(6);
