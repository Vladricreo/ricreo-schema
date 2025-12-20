-- NOTE:
-- Questa migrazione rende "AmazonSalesData" più robusta e idempotente:
-- - uniqueIdentifier diventa NOT NULL
-- - aggiungiamo unique(fbaProductId, date) per impedire duplicati giornalieri
--
-- Include una bonifica dati per evitare failure in presenza di record storici con:
-- - uniqueIdentifier NULL / vuoto
-- - duplicati per (fbaProductId, date) o per uniqueIdentifier

-- 1) Backfill uniqueIdentifier dove manca (o è vuoto)
UPDATE "inventory"."AmazonSalesData"
SET "uniqueIdentifier" = UPPER(COALESCE("sku", 'UNKNOWN')) || '-' || TO_CHAR("date", 'YYYY-MM-DD')
WHERE "uniqueIdentifier" IS NULL OR BTRIM("uniqueIdentifier") = '';

-- 2) Deduplica per uniqueIdentifier (teniamo il record con unitsSold maggiore)
WITH ranked AS (
  SELECT
    "id",
    "uniqueIdentifier",
    ROW_NUMBER() OVER (
      PARTITION BY "uniqueIdentifier"
      ORDER BY "unitsSold" DESC, "id" ASC
    ) AS rn
  FROM "inventory"."AmazonSalesData"
)
DELETE FROM "inventory"."AmazonSalesData" a
USING ranked r
WHERE a."id" = r."id"
  AND r.rn > 1;

-- 3) Deduplica per (fbaProductId, date) (teniamo il record con unitsSold maggiore)
WITH ranked AS (
  SELECT
    "id",
    "fbaProductId",
    "date",
    ROW_NUMBER() OVER (
      PARTITION BY "fbaProductId", "date"
      ORDER BY "unitsSold" DESC, "id" ASC
    ) AS rn
  FROM "inventory"."AmazonSalesData"
)
DELETE FROM "inventory"."AmazonSalesData" a
USING ranked r
WHERE a."id" = r."id"
  AND r.rn > 1;

-- 4) Applica i vincoli
ALTER TABLE "inventory"."AmazonSalesData"
  ALTER COLUMN "uniqueIdentifier" SET NOT NULL;

CREATE UNIQUE INDEX "AmazonSalesData_fbaProductId_date_key"
  ON "inventory"."AmazonSalesData"("fbaProductId", "date");

