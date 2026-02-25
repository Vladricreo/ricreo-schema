-- Aggiunge campo per tracciare i grammi già dedotti dalla spool durante gli snapshot progressivi.
-- Permette all'harvest di dedurre solo il delta residuo, evitando doppia deduzione.
ALTER TABLE "print-farm"."PrintRunMetrics"
ADD COLUMN IF NOT EXISTS "snapshotDeductedGrams" DECIMAL(12, 2);
