-- Partial unique indexes for nullable keys.
-- Postgres UNIQUE allows multiple NULLs, so we add partial indexes
-- to enforce uniqueness when materialCategoryId IS NULL.

-- 1) PrinterEnergyDailySlice: one row per (day, printerId, phase) when category is NULL
CREATE UNIQUE INDEX IF NOT EXISTS "PrinterEnergyDailySlice_unique_null_category"
ON "print-farm"."PrinterEnergyDailySlice" (day, "printerId", "phase")
WHERE "materialCategoryId" IS NULL;

-- 2) PrinterModelEnergyProfile: one row per (printerModelId, voltage, phase) when category is NULL
CREATE UNIQUE INDEX IF NOT EXISTS "PrinterModelEnergyProfile_unique_null_category"
ON "print-farm"."PrinterModelEnergyProfile" ("printerModelId", "voltage", "phase")
WHERE "materialCategoryId" IS NULL;

