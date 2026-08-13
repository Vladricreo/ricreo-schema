-- Periodi di override stampante (manutenzione / disabilitata / stampa manuale)
-- con ingresso e uscita, per il grafico utilizzo e per audit operatore.

CREATE TABLE IF NOT EXISTS "print-farm"."PrinterOverridePeriod" (
  "id" UUID NOT NULL,
  "printerId" UUID NOT NULL,
  "status" "print-farm"."PrinterManualOverrideStatus" NOT NULL,
  "startedAt" TIMESTAMPTZ(6) NOT NULL,
  "endedAt" TIMESTAMPTZ(6),
  "setByUserId" TEXT,
  "clearedByUserId" TEXT,
  "reason" TEXT,
  "source" TEXT,
  "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "PrinterOverridePeriod_pkey" PRIMARY KEY ("id")
);

ALTER TABLE "print-farm"."PrinterOverridePeriod"
  ADD CONSTRAINT "PrinterOverridePeriod_printerId_fkey"
  FOREIGN KEY ("printerId") REFERENCES "print-farm"."Printer"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

CREATE INDEX IF NOT EXISTS "PrinterOverridePeriod_printerId_startedAt_idx"
  ON "print-farm"."PrinterOverridePeriod" ("printerId", "startedAt");

CREATE INDEX IF NOT EXISTS "PrinterOverridePeriod_printerId_endedAt_idx"
  ON "print-farm"."PrinterOverridePeriod" ("printerId", "endedAt");

CREATE INDEX IF NOT EXISTS "PrinterOverridePeriod_status_endedAt_idx"
  ON "print-farm"."PrinterOverridePeriod" ("status", "endedAt");

-- Un solo periodo aperto per stampante.
CREATE UNIQUE INDEX IF NOT EXISTS "PrinterOverridePeriod_one_open_per_printer"
  ON "print-farm"."PrinterOverridePeriod" ("printerId")
  WHERE "endedAt" IS NULL;

-- Chiude i PrintRun FAILED "fantasma" (start mai confermato, finishedAt NULL):
-- finestra di durata zero cosi' non gonfiano l'utilizzo. printTimeMinutes=0
-- fa vincere il ramo durata-zero rispetto alla stima del file 3MF.
UPDATE "print-farm"."PrintRun"
SET
  "finishedAt" = COALESCE("createdAt", NOW()),
  "printTimeMinutes" = COALESCE("printTimeMinutes", 0),
  "updatedAt" = NOW()
WHERE status = 'FAILED'
  AND "finishedAt" IS NULL;

-- Backfill periodi chiusi dalle sessioni ISO di manutenzione (createdAt -> endedAt).
INSERT INTO "print-farm"."PrinterOverridePeriod" (
  "id", "printerId", "status", "startedAt", "endedAt", "setByUserId", "reason", "source"
)
SELECT
  gen_random_uuid(),
  m."printerId",
  'MAINTENANCE'::"print-farm"."PrinterManualOverrideStatus",
  m."createdAt",
  m."endedAt",
  m."performedBy",
  m."reason",
  'backfill_maintenance_log'
FROM "print-farm"."PrinterMaintenanceLog" m
WHERE m."endedAt" IS NOT NULL
  AND m."endedAt" > m."createdAt";

-- Periodo aperto per le stampanti attualmente in override (se non gia' coperto).
INSERT INTO "print-farm"."PrinterOverridePeriod" (
  "id", "printerId", "status", "startedAt", "setByUserId", "reason", "source"
)
SELECT
  gen_random_uuid(),
  p.id,
  p."manualOverrideStatus",
  COALESCE(p."manualOverrideAt", p."updatedAt", NOW()),
  p."manualOverrideBy",
  p."manualOverrideReason",
  'backfill_current_override'
FROM "print-farm"."Printer" p
WHERE p."manualOverrideStatus" IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM "print-farm"."PrinterOverridePeriod" o
    WHERE o."printerId" = p.id
      AND o."endedAt" IS NULL
  );
