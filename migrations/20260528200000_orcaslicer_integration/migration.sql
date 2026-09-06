-- Integrazione OrcaSlicer (AFKFelix/orca-slicer-api):
-- nuovi enum + tabelle per profili slicer, progetti sorgente multi-piatto e slice job.
-- Idempotente: usa ADD COLUMN IF NOT EXISTS / CREATE TABLE IF NOT EXISTS / DO $$ ... pg_constraint.

-- ─── 1) ENUM ────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'print-farm' AND t.typname = 'SlicerProfileCategory'
  ) THEN
    CREATE TYPE "print-farm"."SlicerProfileCategory" AS ENUM ('PRINTER', 'PROCESS', 'FILAMENT');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'print-farm' AND t.typname = 'SourceProjectStatus'
  ) THEN
    CREATE TYPE "print-farm"."SourceProjectStatus" AS ENUM ('ACTIVE', 'ARCHIVED');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'print-farm' AND t.typname = 'SliceJobStatus'
  ) THEN
    CREATE TYPE "print-farm"."SliceJobStatus" AS ENUM (
      'PENDING', 'RUNNING', 'COMPLETED', 'FAILED', 'CANCELLED'
    );
  END IF;
END $$;

-- ─── 2) Tabella: SlicerProfile ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "print-farm"."SlicerProfile" (
  "id"               UUID                                NOT NULL DEFAULT gen_random_uuid(),
  "category"         "print-farm"."SlicerProfileCategory" NOT NULL,
  "name"             TEXT                                NOT NULL,
  "orcaName"         TEXT                                NOT NULL,
  "bucketPath"       TEXT                                NOT NULL,
  "filesize"         DECIMAL(12, 0),
  "checksum"         TEXT,
  "version"          INTEGER                             NOT NULL DEFAULT 1,
  "syncedVersion"    INTEGER,
  "syncedToOrcaAt"   TIMESTAMPTZ(6),
  "syncError"        TEXT,
  "description"      TEXT,
  "printerModelId"   INTEGER,
  "itemId"           UUID,
  "nozzleDiameter"   DECIMAL(4, 2),
  "createdAt"        TIMESTAMPTZ(6)                      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt"        TIMESTAMPTZ(6)                      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "SlicerProfile_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "SlicerProfile_category_orcaName_key" UNIQUE ("category", "orcaName")
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'SlicerProfile_printerModelId_fkey'
  ) THEN
    ALTER TABLE "print-farm"."SlicerProfile"
      ADD CONSTRAINT "SlicerProfile_printerModelId_fkey"
      FOREIGN KEY ("printerModelId") REFERENCES "print-farm"."PrinterModel"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'SlicerProfile_itemId_fkey'
  ) THEN
    ALTER TABLE "print-farm"."SlicerProfile"
      ADD CONSTRAINT "SlicerProfile_itemId_fkey"
      FOREIGN KEY ("itemId") REFERENCES "inventory"."Item"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS "SlicerProfile_category_idx"
  ON "print-farm"."SlicerProfile" ("category");
CREATE INDEX IF NOT EXISTS "SlicerProfile_printerModelId_idx"
  ON "print-farm"."SlicerProfile" ("printerModelId");
CREATE INDEX IF NOT EXISTS "SlicerProfile_itemId_idx"
  ON "print-farm"."SlicerProfile" ("itemId");

-- ─── 3) Tabella: SourceProject ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "print-farm"."SourceProject" (
  "id"                UUID                              NOT NULL DEFAULT gen_random_uuid(),
  "name"              TEXT                              NOT NULL,
  "description"       TEXT,
  "productId"         UUID,
  "bucketPath"        TEXT                              NOT NULL,
  "originalFilename"  TEXT                              NOT NULL,
  "filesize"          DECIMAL(12, 0)                    NOT NULL DEFAULT 0,
  "plateCount"        INTEGER                           NOT NULL DEFAULT 0,
  "version"           INTEGER                           NOT NULL DEFAULT 1,
  "status"            "print-farm"."SourceProjectStatus" NOT NULL DEFAULT 'ACTIVE',
  "previousVersionId" UUID,
  "createdAt"         TIMESTAMPTZ(6)                    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt"         TIMESTAMPTZ(6)                    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "SourceProject_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "SourceProject_previousVersionId_key" UNIQUE ("previousVersionId")
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'SourceProject_productId_fkey'
  ) THEN
    ALTER TABLE "print-farm"."SourceProject"
      ADD CONSTRAINT "SourceProject_productId_fkey"
      FOREIGN KEY ("productId") REFERENCES "inventory"."Product"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'SourceProject_previousVersionId_fkey'
  ) THEN
    ALTER TABLE "print-farm"."SourceProject"
      ADD CONSTRAINT "SourceProject_previousVersionId_fkey"
      FOREIGN KEY ("previousVersionId") REFERENCES "print-farm"."SourceProject"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS "SourceProject_productId_idx"
  ON "print-farm"."SourceProject" ("productId");
CREATE INDEX IF NOT EXISTS "SourceProject_status_idx"
  ON "print-farm"."SourceProject" ("status");
CREATE INDEX IF NOT EXISTS "SourceProject_previousVersionId_idx"
  ON "print-farm"."SourceProject" ("previousVersionId");

-- ─── 4) Tabella: SourceProjectPlate ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "print-farm"."SourceProjectPlate" (
  "id"               UUID            NOT NULL DEFAULT gen_random_uuid(),
  "sourceProjectId"  UUID            NOT NULL,
  "plateNumber"      INTEGER         NOT NULL,
  "productPartId"    UUID,
  "label"            TEXT,
  "notes"            TEXT,
  "createdAt"        TIMESTAMPTZ(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt"        TIMESTAMPTZ(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "SourceProjectPlate_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "SourceProjectPlate_sourceProjectId_plateNumber_key" UNIQUE ("sourceProjectId", "plateNumber")
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'SourceProjectPlate_sourceProjectId_fkey'
  ) THEN
    ALTER TABLE "print-farm"."SourceProjectPlate"
      ADD CONSTRAINT "SourceProjectPlate_sourceProjectId_fkey"
      FOREIGN KEY ("sourceProjectId") REFERENCES "print-farm"."SourceProject"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'SourceProjectPlate_productPartId_fkey'
  ) THEN
    ALTER TABLE "print-farm"."SourceProjectPlate"
      ADD CONSTRAINT "SourceProjectPlate_productPartId_fkey"
      FOREIGN KEY ("productPartId") REFERENCES "inventory"."ProductPart"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS "SourceProjectPlate_productPartId_idx"
  ON "print-farm"."SourceProjectPlate" ("productPartId");

-- ─── 5) Tabella: SliceJob ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "print-farm"."SliceJob" (
  "id"                 UUID                          NOT NULL DEFAULT gen_random_uuid(),
  "sourceProjectId"    UUID                          NOT NULL,
  "sourcePlateId"      UUID                          NOT NULL,
  "plateNumber"        INTEGER                       NOT NULL,
  "productPartId"      UUID,
  "printerModelId"     INTEGER                       NOT NULL,
  "printerProfileId"   UUID                          NOT NULL,
  "processProfileId"   UUID                          NOT NULL,
  "filamentProfileId"  UUID,
  "bedType"            TEXT,
  "status"             "print-farm"."SliceJobStatus" NOT NULL DEFAULT 'PENDING',
  "orcaRequestId"      TEXT,
  "resultFileId"       UUID,
  "errorMessage"       TEXT,
  "printTimeSec"       INTEGER,
  "filamentUsedG"      DECIMAL(12, 2),
  "startedAt"          TIMESTAMPTZ(6),
  "completedAt"        TIMESTAMPTZ(6),
  "createdAt"          TIMESTAMPTZ(6)                NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt"          TIMESTAMPTZ(6)                NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "SliceJob_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "SliceJob_resultFileId_key" UNIQUE ("resultFileId")
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'SliceJob_sourceProjectId_fkey'
  ) THEN
    ALTER TABLE "print-farm"."SliceJob"
      ADD CONSTRAINT "SliceJob_sourceProjectId_fkey"
      FOREIGN KEY ("sourceProjectId") REFERENCES "print-farm"."SourceProject"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'SliceJob_sourcePlateId_fkey'
  ) THEN
    ALTER TABLE "print-farm"."SliceJob"
      ADD CONSTRAINT "SliceJob_sourcePlateId_fkey"
      FOREIGN KEY ("sourcePlateId") REFERENCES "print-farm"."SourceProjectPlate"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'SliceJob_productPartId_fkey'
  ) THEN
    ALTER TABLE "print-farm"."SliceJob"
      ADD CONSTRAINT "SliceJob_productPartId_fkey"
      FOREIGN KEY ("productPartId") REFERENCES "inventory"."ProductPart"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'SliceJob_printerModelId_fkey'
  ) THEN
    ALTER TABLE "print-farm"."SliceJob"
      ADD CONSTRAINT "SliceJob_printerModelId_fkey"
      FOREIGN KEY ("printerModelId") REFERENCES "print-farm"."PrinterModel"("id")
      ON DELETE RESTRICT ON UPDATE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'SliceJob_printerProfileId_fkey'
  ) THEN
    ALTER TABLE "print-farm"."SliceJob"
      ADD CONSTRAINT "SliceJob_printerProfileId_fkey"
      FOREIGN KEY ("printerProfileId") REFERENCES "print-farm"."SlicerProfile"("id")
      ON DELETE RESTRICT ON UPDATE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'SliceJob_processProfileId_fkey'
  ) THEN
    ALTER TABLE "print-farm"."SliceJob"
      ADD CONSTRAINT "SliceJob_processProfileId_fkey"
      FOREIGN KEY ("processProfileId") REFERENCES "print-farm"."SlicerProfile"("id")
      ON DELETE RESTRICT ON UPDATE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'SliceJob_filamentProfileId_fkey'
  ) THEN
    ALTER TABLE "print-farm"."SliceJob"
      ADD CONSTRAINT "SliceJob_filamentProfileId_fkey"
      FOREIGN KEY ("filamentProfileId") REFERENCES "print-farm"."SlicerProfile"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'SliceJob_resultFileId_fkey'
  ) THEN
    ALTER TABLE "print-farm"."SliceJob"
      ADD CONSTRAINT "SliceJob_resultFileId_fkey"
      FOREIGN KEY ("resultFileId") REFERENCES "print-farm"."ProjectThreeMFFile"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS "SliceJob_sourceProjectId_idx"
  ON "print-farm"."SliceJob" ("sourceProjectId");
CREATE INDEX IF NOT EXISTS "SliceJob_sourcePlateId_idx"
  ON "print-farm"."SliceJob" ("sourcePlateId");
CREATE INDEX IF NOT EXISTS "SliceJob_productPartId_idx"
  ON "print-farm"."SliceJob" ("productPartId");
CREATE INDEX IF NOT EXISTS "SliceJob_printerModelId_idx"
  ON "print-farm"."SliceJob" ("printerModelId");
CREATE INDEX IF NOT EXISTS "SliceJob_status_idx"
  ON "print-farm"."SliceJob" ("status");
CREATE INDEX IF NOT EXISTS "SliceJob_orcaRequestId_idx"
  ON "print-farm"."SliceJob" ("orcaRequestId");
