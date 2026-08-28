-- Bozze scarico/swap e layer vocale corridoio (Raspberry Pi + OpenAI).

ALTER TABLE "print-farm"."CorridorMonitor"
  ADD COLUMN IF NOT EXISTS "voiceOverlay" JSONB;

CREATE TABLE IF NOT EXISTS "print-farm"."HarvestDraft" (
  "id"                    UUID NOT NULL DEFAULT gen_random_uuid(),
  "assignmentId"          UUID NOT NULL,
  "printerId"             UUID NOT NULL,
  "aisleCode"             TEXT NOT NULL,
  "partsAccepted"         INTEGER NOT NULL,
  "partsRejected"         INTEGER NOT NULL DEFAULT 0,
  "odetteId"              UUID,
  "odetteSource"          TEXT NOT NULL DEFAULT 'SUGGESTED',
  "targetLocationId"      UUID,
  "markOdetteFull"        BOOLEAN NOT NULL DEFAULT false,
  "rejectReason"          TEXT,
  "setMaintenance"        BOOLEAN NOT NULL DEFAULT false,
  "note"                  TEXT,
  "assignmentUpdatedAt"   TIMESTAMPTZ(6) NOT NULL,
  "computedSignature"     TEXT NOT NULL,
  "state"                 TEXT NOT NULL DEFAULT 'DRAFT',
  "lastTouchedBy"         TEXT,
  "createdAt"             TIMESTAMPTZ(6) NOT NULL DEFAULT now(),
  "updatedAt"             TIMESTAMPTZ(6) NOT NULL DEFAULT now(),
  CONSTRAINT "HarvestDraft_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "HarvestDraft_assignmentId_key"
  ON "print-farm"."HarvestDraft" ("assignmentId");
CREATE INDEX IF NOT EXISTS "HarvestDraft_printerId_idx"
  ON "print-farm"."HarvestDraft" ("printerId");
CREATE INDEX IF NOT EXISTS "HarvestDraft_aisleCode_state_idx"
  ON "print-farm"."HarvestDraft" ("aisleCode", "state");
CREATE INDEX IF NOT EXISTS "HarvestDraft_odetteId_idx"
  ON "print-farm"."HarvestDraft" ("odetteId");

CREATE TABLE IF NOT EXISTS "print-farm"."SpoolSwapDraft" (
  "id"                       UUID NOT NULL DEFAULT gen_random_uuid(),
  "printerId"                UUID NOT NULL,
  "aisleCode"                TEXT NOT NULL,
  "rowKey"                   TEXT NOT NULL,
  "trigger"                  TEXT NOT NULL DEFAULT 'SWAP',
  "fromSpoolId"              UUID,
  "toSpoolId"                UUID,
  "toTagCode"                TEXT,
  "unloadTargetLocationId"   UUID,
  "computedSignature"        TEXT NOT NULL,
  "state"                    TEXT NOT NULL DEFAULT 'DRAFT',
  "lastTouchedBy"            TEXT,
  "createdAt"                TIMESTAMPTZ(6) NOT NULL DEFAULT now(),
  "updatedAt"                TIMESTAMPTZ(6) NOT NULL DEFAULT now(),
  CONSTRAINT "SpoolSwapDraft_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "SpoolSwapDraft_printerId_rowKey_key"
  ON "print-farm"."SpoolSwapDraft" ("printerId", "rowKey");
CREATE INDEX IF NOT EXISTS "SpoolSwapDraft_aisleCode_state_idx"
  ON "print-farm"."SpoolSwapDraft" ("aisleCode", "state");

CREATE TABLE IF NOT EXISTS "print-farm"."VoiceDevice" (
  "id"                UUID NOT NULL DEFAULT gen_random_uuid(),
  "name"              TEXT NOT NULL,
  "aisleCode"         TEXT NOT NULL,
  "deviceToken"       TEXT NOT NULL,
  "boundOperatorId"   INTEGER,
  "enabled"           BOOLEAN NOT NULL DEFAULT true,
  "lastSeenAt"        TIMESTAMPTZ(6),
  "corridorMonitorId" UUID,
  "createdAt"         TIMESTAMPTZ(6) NOT NULL DEFAULT now(),
  "updatedAt"         TIMESTAMPTZ(6) NOT NULL DEFAULT now(),
  CONSTRAINT "VoiceDevice_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "VoiceDevice_deviceToken_key"
  ON "print-farm"."VoiceDevice" ("deviceToken");
CREATE INDEX IF NOT EXISTS "VoiceDevice_aisleCode_idx"
  ON "print-farm"."VoiceDevice" ("aisleCode");
CREATE INDEX IF NOT EXISTS "VoiceDevice_boundOperatorId_idx"
  ON "print-farm"."VoiceDevice" ("boundOperatorId");

CREATE TABLE IF NOT EXISTS "print-farm"."VoiceSession" (
  "id"            UUID NOT NULL DEFAULT gen_random_uuid(),
  "deviceId"      UUID NOT NULL,
  "operatorId"    INTEGER NOT NULL,
  "snapshot"      JSONB NOT NULL DEFAULT '{}'::jsonb,
  "turns"         JSONB NOT NULL DEFAULT '[]'::jsonb,
  "pendingIntent" JSONB,
  "expiresAt"     TIMESTAMPTZ(6) NOT NULL,
  "createdAt"     TIMESTAMPTZ(6) NOT NULL DEFAULT now(),
  "updatedAt"     TIMESTAMPTZ(6) NOT NULL DEFAULT now(),
  CONSTRAINT "VoiceSession_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "VoiceSession_deviceId_expiresAt_idx"
  ON "print-farm"."VoiceSession" ("deviceId", "expiresAt");
CREATE INDEX IF NOT EXISTS "VoiceSession_operatorId_idx"
  ON "print-farm"."VoiceSession" ("operatorId");

CREATE TABLE IF NOT EXISTS "print-farm"."VoiceCommandLog" (
  "id"             UUID NOT NULL DEFAULT gen_random_uuid(),
  "sessionId"      UUID,
  "deviceId"       UUID NOT NULL,
  "operatorId"     INTEGER NOT NULL,
  "transcript"     TEXT NOT NULL,
  "tool"           TEXT,
  "args"           JSONB,
  "status"         TEXT NOT NULL,
  "errorMessage"   TEXT,
  "latencyMs"      INTEGER,
  "replyText"      TEXT,
  "idempotencyKey" TEXT NOT NULL,
  "createdAt"      TIMESTAMPTZ(6) NOT NULL DEFAULT now(),
  CONSTRAINT "VoiceCommandLog_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "VoiceCommandLog_idempotencyKey_key"
  ON "print-farm"."VoiceCommandLog" ("idempotencyKey");
CREATE INDEX IF NOT EXISTS "VoiceCommandLog_deviceId_createdAt_idx"
  ON "print-farm"."VoiceCommandLog" ("deviceId", "createdAt");
CREATE INDEX IF NOT EXISTS "VoiceCommandLog_operatorId_createdAt_idx"
  ON "print-farm"."VoiceCommandLog" ("operatorId", "createdAt");
CREATE INDEX IF NOT EXISTS "VoiceCommandLog_status_createdAt_idx"
  ON "print-farm"."VoiceCommandLog" ("status", "createdAt");

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'HarvestDraft_assignmentId_fkey') THEN
    ALTER TABLE "print-farm"."HarvestDraft"
      ADD CONSTRAINT "HarvestDraft_assignmentId_fkey"
      FOREIGN KEY ("assignmentId") REFERENCES "print-farm"."PrinterAssignment"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'HarvestDraft_printerId_fkey') THEN
    ALTER TABLE "print-farm"."HarvestDraft"
      ADD CONSTRAINT "HarvestDraft_printerId_fkey"
      FOREIGN KEY ("printerId") REFERENCES "print-farm"."Printer"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'HarvestDraft_odetteId_fkey') THEN
    ALTER TABLE "print-farm"."HarvestDraft"
      ADD CONSTRAINT "HarvestDraft_odetteId_fkey"
      FOREIGN KEY ("odetteId") REFERENCES "inventory"."Odette"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'HarvestDraft_targetLocationId_fkey') THEN
    ALTER TABLE "print-farm"."HarvestDraft"
      ADD CONSTRAINT "HarvestDraft_targetLocationId_fkey"
      FOREIGN KEY ("targetLocationId") REFERENCES "inventory"."WarehouseLocation"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'SpoolSwapDraft_printerId_fkey') THEN
    ALTER TABLE "print-farm"."SpoolSwapDraft"
      ADD CONSTRAINT "SpoolSwapDraft_printerId_fkey"
      FOREIGN KEY ("printerId") REFERENCES "print-farm"."Printer"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'SpoolSwapDraft_fromSpoolId_fkey') THEN
    ALTER TABLE "print-farm"."SpoolSwapDraft"
      ADD CONSTRAINT "SpoolSwapDraft_fromSpoolId_fkey"
      FOREIGN KEY ("fromSpoolId") REFERENCES "print-farm"."FilamentSpool"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'SpoolSwapDraft_toSpoolId_fkey') THEN
    ALTER TABLE "print-farm"."SpoolSwapDraft"
      ADD CONSTRAINT "SpoolSwapDraft_toSpoolId_fkey"
      FOREIGN KEY ("toSpoolId") REFERENCES "print-farm"."FilamentSpool"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'SpoolSwapDraft_unloadTargetLocationId_fkey') THEN
    ALTER TABLE "print-farm"."SpoolSwapDraft"
      ADD CONSTRAINT "SpoolSwapDraft_unloadTargetLocationId_fkey"
      FOREIGN KEY ("unloadTargetLocationId") REFERENCES "inventory"."WarehouseLocation"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'VoiceDevice_boundOperatorId_fkey') THEN
    ALTER TABLE "print-farm"."VoiceDevice"
      ADD CONSTRAINT "VoiceDevice_boundOperatorId_fkey"
      FOREIGN KEY ("boundOperatorId") REFERENCES "public"."User"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'VoiceDevice_corridorMonitorId_fkey') THEN
    ALTER TABLE "print-farm"."VoiceDevice"
      ADD CONSTRAINT "VoiceDevice_corridorMonitorId_fkey"
      FOREIGN KEY ("corridorMonitorId") REFERENCES "print-farm"."CorridorMonitor"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'VoiceSession_deviceId_fkey') THEN
    ALTER TABLE "print-farm"."VoiceSession"
      ADD CONSTRAINT "VoiceSession_deviceId_fkey"
      FOREIGN KEY ("deviceId") REFERENCES "print-farm"."VoiceDevice"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'VoiceSession_operatorId_fkey') THEN
    ALTER TABLE "print-farm"."VoiceSession"
      ADD CONSTRAINT "VoiceSession_operatorId_fkey"
      FOREIGN KEY ("operatorId") REFERENCES "public"."User"("id")
      ON DELETE RESTRICT ON UPDATE CASCADE;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'VoiceCommandLog_sessionId_fkey') THEN
    ALTER TABLE "print-farm"."VoiceCommandLog"
      ADD CONSTRAINT "VoiceCommandLog_sessionId_fkey"
      FOREIGN KEY ("sessionId") REFERENCES "print-farm"."VoiceSession"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'VoiceCommandLog_deviceId_fkey') THEN
    ALTER TABLE "print-farm"."VoiceCommandLog"
      ADD CONSTRAINT "VoiceCommandLog_deviceId_fkey"
      FOREIGN KEY ("deviceId") REFERENCES "print-farm"."VoiceDevice"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'VoiceCommandLog_operatorId_fkey') THEN
    ALTER TABLE "print-farm"."VoiceCommandLog"
      ADD CONSTRAINT "VoiceCommandLog_operatorId_fkey"
      FOREIGN KEY ("operatorId") REFERENCES "public"."User"("id")
      ON DELETE RESTRICT ON UPDATE CASCADE;
  END IF;
END $$;
