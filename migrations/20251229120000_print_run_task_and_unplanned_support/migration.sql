/*
  Migrazione: estende "print-farm"."PrintRun" per supportare:
  - run non pianificate (printerId diretto, fileId nullable)
  - correlazione runtime (taskId, taskFileName, detectedAt)
  - audit origine (source)

  NOTE:
  - `taskId` NON è unico (0..999, riusato nel tempo e tra stampanti) → indicizzare ma NON mettere unique.
  - `fileId` diventa nullable per poter creare PrintRun anche quando il file non è presente in DB.
*/

-- 1) Enum per origine PrintRun (schema: print-farm)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type t
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE t.typname = 'PrintRunSource' AND n.nspname = 'print-farm'
  ) THEN
    CREATE TYPE "print-farm"."PrintRunSource" AS ENUM ('UI', 'PRINTER', 'SYSTEM');
  END IF;
END
$$;

-- 2) Colonne nuove (tutte additive e compatibili)
ALTER TABLE "print-farm"."PrintRun"
  ADD COLUMN IF NOT EXISTS "printerId" UUID,
  ADD COLUMN IF NOT EXISTS "taskId" SMALLINT,
  ADD COLUMN IF NOT EXISTS "taskFileName" TEXT,
  ADD COLUMN IF NOT EXISTS "detectedAt" TIMESTAMPTZ(6),
  ADD COLUMN IF NOT EXISTS "source" "print-farm"."PrintRunSource" NOT NULL DEFAULT 'UI';

-- 3) `fileId` nullable (supporto run unplanned)
ALTER TABLE "print-farm"."PrintRun"
  ALTER COLUMN "fileId" DROP NOT NULL;

-- 4) FK verso Printer (per run unplanned)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'PrintRun_printerId_fkey'
  ) THEN
    ALTER TABLE "print-farm"."PrintRun"
      ADD CONSTRAINT "PrintRun_printerId_fkey"
      FOREIGN KEY ("printerId")
      REFERENCES "print-farm"."Printer"("id")
      ON DELETE SET NULL
      ON UPDATE CASCADE;
  END IF;
END
$$;

-- 5) Indici (migliorano lookup correlazione)
CREATE INDEX IF NOT EXISTS "PrintRun_printerId_idx" ON "print-farm"."PrintRun"("printerId");
CREATE INDEX IF NOT EXISTS "PrintRun_printerId_taskId_idx" ON "print-farm"."PrintRun"("printerId", "taskId");


