-- Multi-nozzle + Multi-AMS — schema additivo (Step 1 di docs/multi-nozzle-multi-ams-support.md).
-- Aggiunge:
--   • Colonne nuove su "Printer" (nozzleCount, filaTrackSwitch*, activeExtruder, lastPrintFilamentMap)
--   • Colonna "extruderId" su "ProjectFileMaterial"
--   • Nuovi model: PrinterNozzle, PrinterAmsUnit, PrinterExternalSpool
--   • FK opzionale "amsUnitId" su PrinterAmsSlot verso PrinterAmsUnit
-- Idempotente: sicuro da rieseguire (uso ADD COLUMN IF NOT EXISTS / CREATE TABLE IF NOT EXISTS
-- e DO $$ … pg_constraint per le FK).
-- Nessuna colonna legacy viene rimossa: i consumer attuali continuano a leggere
-- "Printer.nozzleDiameter / nozzleType / amsModel / currentSpoolId / externalReported*".

-- ─── 1) Printer: nuove colonne multi-nozzle ─────────────────────────────────
ALTER TABLE "print-farm"."Printer"
  ADD COLUMN IF NOT EXISTS "nozzleCount" INTEGER NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS "filaTrackSwitchInstalled" BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS "filaTrackSwitchState" JSONB,
  ADD COLUMN IF NOT EXISTS "activeExtruder" INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "lastPrintFilamentMap" INTEGER[] DEFAULT ARRAY[]::INTEGER[];

COMMENT ON COLUMN "print-farm"."Printer"."nozzleCount"
  IS 'Numero di nozzle/extruder (1 single, 2 dual H2D/X2D). Autodetect via MQTT.';
COMMENT ON COLUMN "print-farm"."Printer"."filaTrackSwitchInstalled"
  IS 'True se la stampante ha il Filament Track Switch installato (solo dual-nozzle).';
COMMENT ON COLUMN "print-farm"."Printer"."filaTrackSwitchState"
  IS 'Snapshot dell''ultimo stato fila_switch riportato dal firmware (JSON).';
COMMENT ON COLUMN "print-farm"."Printer"."activeExtruder"
  IS 'Ultimo extruder attivo riportato dalla stampante (0=right, 1=left).';
COMMENT ON COLUMN "print-farm"."Printer"."lastPrintFilamentMap"
  IS 'Mapping per-filamento → extruderId dell''ultimo job (parallelo a lastPrintAmsMapping).';

-- ─── 2) ProjectFileMaterial: extruderId dal 3MF ─────────────────────────────
ALTER TABLE "print-farm"."ProjectFileMaterial"
  ADD COLUMN IF NOT EXISTS "extruderId" INTEGER;

COMMENT ON COLUMN "print-farm"."ProjectFileMaterial"."extruderId"
  IS 'Extruder dichiarato dal file Bambu (0=right, 1=left). Null se single-nozzle o non specificato.';

-- ─── 3) Tabella: PrinterNozzle ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "print-farm"."PrinterNozzle" (
  "id"                        UUID            NOT NULL DEFAULT gen_random_uuid(),
  "printerId"                 UUID            NOT NULL,
  "extruderId"                INTEGER         NOT NULL,
  "diameter"                  DECIMAL(4, 2)   NOT NULL DEFAULT 0.4,
  "nozzleType"                TEXT            NOT NULL DEFAULT 'Hardened Steel',
  "wear"                      INTEGER,
  "serialNumber"              TEXT,
  "maxTempC"                  INTEGER,
  "lastReportedFilamentColor" TEXT,
  "lastReportedFilamentType"  TEXT,
  "createdAt"                 TIMESTAMPTZ(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt"                 TIMESTAMPTZ(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "PrinterNozzle_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "PrinterNozzle_printerId_extruderId_key" UNIQUE ("printerId", "extruderId")
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'PrinterNozzle_printerId_fkey'
  ) THEN
    ALTER TABLE "print-farm"."PrinterNozzle"
      ADD CONSTRAINT "PrinterNozzle_printerId_fkey"
      FOREIGN KEY ("printerId") REFERENCES "print-farm"."Printer"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS "PrinterNozzle_printerId_idx"
  ON "print-farm"."PrinterNozzle" ("printerId");

-- ─── 4) Tabella: PrinterAmsUnit ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "print-farm"."PrinterAmsUnit" (
  "id"              UUID            NOT NULL DEFAULT gen_random_uuid(),
  "printerId"       UUID            NOT NULL,
  "amsId"           INTEGER         NOT NULL,
  "amsModel"        "print-farm"."AmsModel" NOT NULL,
  "serialNumber"    TEXT,
  "firmwareVersion" TEXT,
  "extruderId"      INTEGER,
  "humidity"        INTEGER,
  "tempC"           DECIMAL(4, 1),
  "dryStatus"       INTEGER,
  "drySubStatus"    INTEGER,
  "dryTimeMin"      INTEGER,
  "createdAt"       TIMESTAMPTZ(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt"       TIMESTAMPTZ(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "PrinterAmsUnit_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "PrinterAmsUnit_printerId_amsId_key" UNIQUE ("printerId", "amsId")
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'PrinterAmsUnit_printerId_fkey'
  ) THEN
    ALTER TABLE "print-farm"."PrinterAmsUnit"
      ADD CONSTRAINT "PrinterAmsUnit_printerId_fkey"
      FOREIGN KEY ("printerId") REFERENCES "print-farm"."Printer"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS "PrinterAmsUnit_printerId_idx"
  ON "print-farm"."PrinterAmsUnit" ("printerId");

-- ─── 5) Tabella: PrinterExternalSpool ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS "print-farm"."PrinterExternalSpool" (
  "id"                   UUID            NOT NULL DEFAULT gen_random_uuid(),
  "printerId"            UUID            NOT NULL,
  "extruderId"           INTEGER         NOT NULL,
  "spoolId"              UUID,
  "reportedMaterialType" TEXT,
  "reportedColor"        TEXT,
  "reportedTrayInfoIdx"  TEXT,
  "reportedLastSeenAt"   TIMESTAMPTZ(6),
  "createdAt"            TIMESTAMPTZ(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt"            TIMESTAMPTZ(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "PrinterExternalSpool_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "PrinterExternalSpool_printerId_extruderId_key" UNIQUE ("printerId", "extruderId"),
  CONSTRAINT "PrinterExternalSpool_spoolId_key" UNIQUE ("spoolId")
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'PrinterExternalSpool_printerId_fkey'
  ) THEN
    ALTER TABLE "print-farm"."PrinterExternalSpool"
      ADD CONSTRAINT "PrinterExternalSpool_printerId_fkey"
      FOREIGN KEY ("printerId") REFERENCES "print-farm"."Printer"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'PrinterExternalSpool_spoolId_fkey'
  ) THEN
    ALTER TABLE "print-farm"."PrinterExternalSpool"
      ADD CONSTRAINT "PrinterExternalSpool_spoolId_fkey"
      FOREIGN KEY ("spoolId") REFERENCES "print-farm"."FilamentSpool"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS "PrinterExternalSpool_printerId_idx"
  ON "print-farm"."PrinterExternalSpool" ("printerId");

-- ─── 6) PrinterAmsSlot.amsUnitId: FK opzionale verso PrinterAmsUnit ─────────
ALTER TABLE "print-farm"."PrinterAmsSlot"
  ADD COLUMN IF NOT EXISTS "amsUnitId" UUID;

COMMENT ON COLUMN "print-farm"."PrinterAmsSlot"."amsUnitId"
  IS 'FK opzionale al PrinterAmsUnit (popolata da backfill). Nullable per back-compat.';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'PrinterAmsSlot_amsUnitId_fkey'
  ) THEN
    ALTER TABLE "print-farm"."PrinterAmsSlot"
      ADD CONSTRAINT "PrinterAmsSlot_amsUnitId_fkey"
      FOREIGN KEY ("amsUnitId") REFERENCES "print-farm"."PrinterAmsUnit"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS "PrinterAmsSlot_amsUnitId_idx"
  ON "print-farm"."PrinterAmsSlot" ("amsUnitId");
