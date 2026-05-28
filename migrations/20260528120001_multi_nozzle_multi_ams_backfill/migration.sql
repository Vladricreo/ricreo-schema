-- Multi-nozzle + Multi-AMS — backfill dati (Step 2 di docs/multi-nozzle-multi-ams-support.md).
-- Popola i nuovi model (PrinterNozzle / PrinterAmsUnit / PrinterExternalSpool) e la FK
-- "PrinterAmsSlot.amsUnitId" partendo dai dati legacy presenti su "Printer" e "PrinterAmsSlot".
--
-- Idempotente: tutti gli INSERT usano ON CONFLICT DO NOTHING e l'UPDATE è limitato ai record
-- con "amsUnitId" ancora NULL. Sicuro da rieseguire (es. doppio deploy / replay manuale).
--
-- Strategia: TUTTI i printer hanno almeno un PrinterNozzle(extruderId=0). I record AMS vengono
-- derivati dai distinct (printerId, amsUnit) già presenti in PrinterAmsSlot (per coprire i casi
-- in cui esistono più AMS oggi). Per printer con amsModel valorizzato ma senza slot, creiamo
-- un fallback con amsId=0.

-- ─── 1) PrinterNozzle: 1 record per printer, extruderId=0 ───────────────────
-- Eredita diametro e tipo dai campi legacy del Printer.
INSERT INTO "print-farm"."PrinterNozzle" (
  "id", "printerId", "extruderId", "diameter", "nozzleType", "createdAt", "updatedAt"
)
SELECT
  gen_random_uuid(),
  p."id",
  0,
  p."nozzleDiameter",
  p."nozzleType",
  NOW(),
  NOW()
FROM "print-farm"."Printer" p
ON CONFLICT ("printerId", "extruderId") DO NOTHING;

-- ─── 2) PrinterAmsUnit: 1 record per ogni (printerId, amsUnit) già in uso ──
-- Copre i casi in cui un printer ha più AMS (amsUnit > 0) configurati nello schema attuale.
INSERT INTO "print-farm"."PrinterAmsUnit" (
  "id", "printerId", "amsId", "amsModel", "extruderId", "createdAt", "updatedAt"
)
SELECT
  gen_random_uuid(),
  s."printerId",
  s."amsUnit",
  COALESCE(p."amsModel", 'AMS'),
  0,
  NOW(),
  NOW()
FROM (
  SELECT DISTINCT "printerId", "amsUnit"
  FROM "print-farm"."PrinterAmsSlot"
) s
JOIN "print-farm"."Printer" p ON p."id" = s."printerId"
ON CONFLICT ("printerId", "amsId") DO NOTHING;

-- ─── 2b) Fallback: printer con amsModel valorizzato ma SENZA slot in PrinterAmsSlot ──
-- (es. AMS_HT con 1 sola slot che non è ancora stata creata, o stampante con AMS ma vuoto).
INSERT INTO "print-farm"."PrinterAmsUnit" (
  "id", "printerId", "amsId", "amsModel", "extruderId", "createdAt", "updatedAt"
)
SELECT
  gen_random_uuid(),
  p."id",
  0,
  p."amsModel",
  0,
  NOW(),
  NOW()
FROM "print-farm"."Printer" p
WHERE p."amsModel" IS NOT NULL
ON CONFLICT ("printerId", "amsId") DO NOTHING;

-- ─── 3) PrinterAmsSlot.amsUnitId: lookup join ───────────────────────────────
-- Collega ogni slot esistente al PrinterAmsUnit appena creato.
UPDATE "print-farm"."PrinterAmsSlot" s
SET "amsUnitId" = u."id"
FROM "print-farm"."PrinterAmsUnit" u
WHERE s."printerId" = u."printerId"
  AND s."amsUnit" = u."amsId"
  AND s."amsUnitId" IS NULL;

-- ─── 4) PrinterExternalSpool: 1 record per printer con currentSpoolId o reported ──
-- Sposta i campi legacy "Printer.currentSpoolId" + "Printer.externalReported*" nel nuovo model
-- (extruderId=0 per back-compat single-nozzle). I campi legacy restano scrivibili per 1-2 release.
INSERT INTO "print-farm"."PrinterExternalSpool" (
  "id", "printerId", "extruderId", "spoolId",
  "reportedMaterialType", "reportedColor", "reportedTrayInfoIdx", "reportedLastSeenAt",
  "createdAt", "updatedAt"
)
SELECT
  gen_random_uuid(),
  p."id",
  0,
  p."currentSpoolId",
  p."externalReportedMaterialType",
  p."externalReportedColor",
  p."externalReportedTrayInfoIdx",
  p."externalReportedLastSeenAt",
  NOW(),
  NOW()
FROM "print-farm"."Printer" p
WHERE p."currentSpoolId" IS NOT NULL
   OR p."externalReportedMaterialType" IS NOT NULL
   OR p."externalReportedColor" IS NOT NULL
   OR p."externalReportedTrayInfoIdx" IS NOT NULL
ON CONFLICT ("printerId", "extruderId") DO NOTHING;
