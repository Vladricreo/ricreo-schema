-- EnergyMonitor usa:
--   ON CONFLICT (day, "printerId", "phase") WHERE "materialCategoryId" IS NULL
-- L'@@unique a 4 colonne non basta: in Postgres i NULL sono distinti, quindi
-- senza questo indice parziale l'upsert standby solleva 42P10.

-- Consolida eventuali duplicati NULL-category prima di creare l'indice.
UPDATE "print-farm"."PrinterEnergyDailySlice" AS s
SET
  kwh = agg.total_kwh,
  "updatedAt" = now()
FROM (
  SELECT
    day,
    "printerId",
    phase,
    SUM(kwh) AS total_kwh,
    (ARRAY_AGG(id ORDER BY "updatedAt" DESC, "createdAt" DESC, id))[1] AS keep_id
  FROM "print-farm"."PrinterEnergyDailySlice"
  WHERE "materialCategoryId" IS NULL
  GROUP BY day, "printerId", phase
  HAVING COUNT(*) > 1
) AS agg
WHERE s.id = agg.keep_id;

DELETE FROM "print-farm"."PrinterEnergyDailySlice" AS s
USING (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY day, "printerId", phase
      ORDER BY "updatedAt" DESC, "createdAt" DESC, id
    ) AS rn
  FROM "print-farm"."PrinterEnergyDailySlice"
  WHERE "materialCategoryId" IS NULL
) AS d
WHERE s.id = d.id
  AND d.rn > 1;

CREATE UNIQUE INDEX IF NOT EXISTS "PrinterEnergyDailySlice_day_printerId_phase_null_category_key"
ON "print-farm"."PrinterEnergyDailySlice" (day, "printerId", phase)
WHERE "materialCategoryId" IS NULL;
