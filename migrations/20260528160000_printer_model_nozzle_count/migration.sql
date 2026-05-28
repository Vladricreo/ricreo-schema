-- Sposta la "verità" del numero di nozzle dalla singola Printer al PrinterModel.
-- Riferimento: docs/multi-nozzle-multi-ams-support.md (Step 4f).
--
-- Comportamento:
--   • Aggiunge "PrinterModel"."nozzleCount" (default 1).
--   • Backfilla da "Printer"."nozzleCount" usando il valore di MAGGIORANZA per modello.
--     In caso di parità, la query sceglie il valore più alto (priorità a 2).
--     Se un modello non ha stampanti, resta a 1.
--   • Mantiene "Printer"."nozzleCount" come mirror per back-compat con i consumer
--     esistenti (scheduler, scoring, prepare-start, ecc.). Verrà tenuto allineato
--     dall'API quando si crea/modifica una stampante o si cambia il PrinterModel.
--
-- Idempotente: sicuro da rieseguire (ADD COLUMN IF NOT EXISTS + UPDATE basato sul join).

-- ─── 1) PrinterModel.nozzleCount ────────────────────────────────────────────
ALTER TABLE "print-farm"."PrinterModel"
  ADD COLUMN IF NOT EXISTS "nozzleCount" INTEGER NOT NULL DEFAULT 1;

COMMENT ON COLUMN "print-farm"."PrinterModel"."nozzleCount"
  IS 'Numero di nozzle/extruder del modello (1 = single, 2 = dual). Source-of-truth per UI.';

-- ─── 2) Backfill: per ogni PrinterModel imposta il valore più frequente
--                  fra le sue Printer.nozzleCount (in caso di parità, MAX). ──
WITH tally AS (
  SELECT
    "modelId",
    "nozzleCount",
    COUNT(*)              AS occurrences,
    ROW_NUMBER() OVER (
      PARTITION BY "modelId"
      ORDER BY COUNT(*) DESC, "nozzleCount" DESC
    )                     AS rank
  FROM "print-farm"."Printer"
  WHERE "nozzleCount" IS NOT NULL
  GROUP BY "modelId", "nozzleCount"
),
winners AS (
  SELECT "modelId", "nozzleCount"
  FROM tally
  WHERE rank = 1
)
UPDATE "print-farm"."PrinterModel" AS pm
SET "nozzleCount" = w."nozzleCount"
FROM winners AS w
WHERE pm."id" = w."modelId"
  AND pm."nozzleCount" <> w."nozzleCount";
