-- CreateEnum (idempotente)
DO $$ BEGIN
  CREATE TYPE "print-farm"."SpoolTagStatus" AS ENUM ('FREE', 'ASSIGNED', 'RETIRED');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- CreateTable: SpoolTag (idempotente)
CREATE TABLE IF NOT EXISTS "print-farm"."SpoolTag" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "code" TEXT NOT NULL,
    "nfcUid" TEXT,
    "status" "print-farm"."SpoolTagStatus" NOT NULL DEFAULT 'FREE',
    "currentSpoolId" UUID,
    "locationId" UUID,
    "notes" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SpoolTag_pkey" PRIMARY KEY ("id")
);

-- Aggiunge locationId se la tabella esisteva già senza questa colonna
ALTER TABLE "print-farm"."SpoolTag" ADD COLUMN IF NOT EXISTS "locationId" UUID;

-- CreateTable: SpoolTagAssignment (idempotente)
CREATE TABLE IF NOT EXISTS "print-farm"."SpoolTagAssignment" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "tagId" UUID NOT NULL,
    "spoolId" UUID NOT NULL,
    "assignedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "unassignedAt" TIMESTAMPTZ(6),

    CONSTRAINT "SpoolTagAssignment_pkey" PRIMARY KEY ("id")
);

-- CreateIndex (idempotenti)
CREATE UNIQUE INDEX IF NOT EXISTS "SpoolTag_code_key" ON "print-farm"."SpoolTag"("code");
CREATE UNIQUE INDEX IF NOT EXISTS "SpoolTag_nfcUid_key" ON "print-farm"."SpoolTag"("nfcUid");
CREATE UNIQUE INDEX IF NOT EXISTS "SpoolTag_currentSpoolId_key" ON "print-farm"."SpoolTag"("currentSpoolId");
CREATE INDEX IF NOT EXISTS "SpoolTag_locationId_idx" ON "print-farm"."SpoolTag"("locationId");
CREATE INDEX IF NOT EXISTS "SpoolTagAssignment_tagId_idx" ON "print-farm"."SpoolTagAssignment"("tagId");
CREATE INDEX IF NOT EXISTS "SpoolTagAssignment_spoolId_idx" ON "print-farm"."SpoolTagAssignment"("spoolId");

-- AddForeignKey (idempotenti con DO/EXCEPTION)
DO $$ BEGIN
  ALTER TABLE "print-farm"."SpoolTag"
      ADD CONSTRAINT "SpoolTag_currentSpoolId_fkey"
      FOREIGN KEY ("currentSpoolId")
      REFERENCES "print-farm"."FilamentSpool"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "print-farm"."SpoolTagAssignment"
      ADD CONSTRAINT "SpoolTagAssignment_tagId_fkey"
      FOREIGN KEY ("tagId")
      REFERENCES "print-farm"."SpoolTag"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "print-farm"."SpoolTagAssignment"
      ADD CONSTRAINT "SpoolTagAssignment_spoolId_fkey"
      FOREIGN KEY ("spoolId")
      REFERENCES "print-farm"."FilamentSpool"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE "print-farm"."SpoolTag"
      ADD CONSTRAINT "SpoolTag_locationId_fkey"
      FOREIGN KEY ("locationId")
      REFERENCES "inventory"."WarehouseLocation"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Migra dati esistenti da nfcTagId a SpoolTag (se la colonna esiste ancora)
INSERT INTO "print-farm"."SpoolTag" ("code", "status", "currentSpoolId")
SELECT
    fs."nfcTagId",
    'ASSIGNED'::"print-farm"."SpoolTagStatus",
    fs."id"
FROM "print-farm"."FilamentSpool" fs
WHERE fs."nfcTagId" IS NOT NULL
  AND fs."nfcTagId" <> ''
ON CONFLICT DO NOTHING;

-- Crea record storico per le tag migrate (solo per quelle senza storico)
INSERT INTO "print-farm"."SpoolTagAssignment" ("tagId", "spoolId")
SELECT st."id", st."currentSpoolId"
FROM "print-farm"."SpoolTag" st
WHERE st."currentSpoolId" IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM "print-farm"."SpoolTagAssignment" sa
    WHERE sa."tagId" = st."id" AND sa."spoolId" = st."currentSpoolId"
  );

-- DropColumn: rimuovi il vecchio campo nfcTagId
ALTER TABLE "print-farm"."FilamentSpool" DROP COLUMN IF EXISTS "nfcTagId";
