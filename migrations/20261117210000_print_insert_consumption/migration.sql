-- R-264 (17/11): corredi inseriti nel pezzo durante la pausa per inserimento.
--
-- 1. ProductToComponent: «Si inserisce in stampa» + parte in cui va. Le righe accese
--    non si consumano più in assemblaggio (Inventory).
-- 2. PrintInsertConsumption: una conferma per stampa × riga distinta, creata dallo
--    scarico (trigger su PrinterHarvest). La conferma in Preparazione crea l'USO.
-- 3. Movement.printInsertConsumptionId: legame movimento ↔ conferma.
--
-- Additiva: colonne nuove con default, tabella nuova, trigger che lavora solo
-- sulle righe distinta con insertedAtPrint = true (nessuna al momento del deploy).

-- ---------------------------------------------------------------------------
-- 1. Distinta
-- ---------------------------------------------------------------------------
ALTER TABLE "inventory"."ProductToComponent"
  ADD COLUMN IF NOT EXISTS "insertedAtPrint" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "insertPartId" UUID,
  ADD COLUMN IF NOT EXISTS "insertedAtPrintSince" TIMESTAMPTZ(6);

ALTER TABLE "inventory"."ProductToComponent"
  ADD CONSTRAINT "ProductToComponent_insertPartId_fkey"
  FOREIGN KEY ("insertPartId") REFERENCES "inventory"."ProductPart"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

CREATE INDEX IF NOT EXISTS "ProductToComponent_insertPartId_idx"
  ON "inventory"."ProductToComponent"("insertPartId");

COMMENT ON COLUMN "inventory"."ProductToComponent"."insertedAtPrint"
  IS 'R-264: il componente si mette nel pezzo in stampa; si consuma alla conferma in Preparazione (PF), non in assemblaggio.';

-- ---------------------------------------------------------------------------
-- 2. Conferme
-- ---------------------------------------------------------------------------
CREATE TABLE "print-farm"."PrintInsertConsumption" (
    "id" UUID NOT NULL,
    "assignmentId" UUID NOT NULL,
    "harvestId" UUID,
    "harvestReverted" BOOLEAN NOT NULL DEFAULT false,
    "productToComponentId" UUID,
    "productPartId" UUID NOT NULL,
    "itemSpecId" UUID NOT NULL,
    "productId" UUID,
    "productOrderId" UUID,
    "printerId" UUID,
    "odetteId" UUID,
    "harvestedAt" TIMESTAMPTZ(6),
    "piecesCount" INTEGER NOT NULL DEFAULT 0,
    "perPiece" DOUBLE PRECISION NOT NULL DEFAULT 1,
    "proposedQty" INTEGER NOT NULL DEFAULT 0,
    "itemId" UUID,
    "confirmedQty" INTEGER,
    "confirmedAt" TIMESTAMPTZ(6),
    "confirmedByUserId" INTEGER,
    "note" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PrintInsertConsumption_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "PrintInsertConsumption_confirmedQty_check" CHECK ("confirmedQty" IS NULL OR "confirmedQty" >= 0)
);

CREATE UNIQUE INDEX "PrintInsertConsumption_assignmentId_productToComponentId_key"
  ON "print-farm"."PrintInsertConsumption"("assignmentId", "productToComponentId");
CREATE INDEX "PrintInsertConsumption_confirmedQty_idx"
  ON "print-farm"."PrintInsertConsumption"("confirmedQty");
CREATE INDEX "PrintInsertConsumption_harvestId_idx"
  ON "print-farm"."PrintInsertConsumption"("harvestId");
CREATE INDEX "PrintInsertConsumption_createdAt_idx"
  ON "print-farm"."PrintInsertConsumption"("createdAt" DESC);

-- Letta e scritta solo via Prisma (postgres, proprietario): RLS senza policy chiude l'accesso anon.
ALTER TABLE "print-farm"."PrintInsertConsumption" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "print-farm"."PrintInsertConsumption"
  ADD CONSTRAINT "PrintInsertConsumption_assignmentId_fkey"
  FOREIGN KEY ("assignmentId") REFERENCES "print-farm"."PrinterAssignment"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "print-farm"."PrintInsertConsumption"
  ADD CONSTRAINT "PrintInsertConsumption_harvestId_fkey"
  FOREIGN KEY ("harvestId") REFERENCES "print-farm"."PrinterHarvest"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "print-farm"."PrintInsertConsumption"
  ADD CONSTRAINT "PrintInsertConsumption_productToComponentId_fkey"
  FOREIGN KEY ("productToComponentId") REFERENCES "inventory"."ProductToComponent"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

-- ---------------------------------------------------------------------------
-- 3. Movimenti
-- ---------------------------------------------------------------------------
ALTER TABLE "inventory"."Movement"
  ADD COLUMN IF NOT EXISTS "printInsertConsumptionId" UUID;
ALTER TABLE "inventory"."Movement"
  ADD CONSTRAINT "Movement_printInsertConsumptionId_fkey"
  FOREIGN KEY ("printInsertConsumptionId") REFERENCES "print-farm"."PrintInsertConsumption"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;
CREATE INDEX IF NOT EXISTS "Movement_printInsertConsumptionId_idx"
  ON "inventory"."Movement"("printInsertConsumptionId");

-- ---------------------------------------------------------------------------
-- 4. Trigger sullo scarico: nasce (o si aggiorna, finché non confermata) la conferma
-- ---------------------------------------------------------------------------
-- Pezzi per parte = buoni + scarti (i corredi restano consumati anche negli scarti).
-- Piatto combinato: righe di partsBreakdown (productPartId, productionJobId).
-- Piatto singolo: parte dell'assignment (o del job) con partsAccepted + partsRejected.
-- Righe distinta legate a uno SKU valgono solo se l'ordine del job è di quello SKU.
CREATE OR REPLACE FUNCTION "print-farm".pf_print_insert_from_harvest()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_breakdown jsonb;
BEGIN
  IF NEW."wasSkipped" THEN
    RETURN NEW;
  END IF;

  -- Corsia veloce: nessuna riga distinta accesa → niente da fare.
  IF NOT EXISTS (SELECT 1 FROM "inventory"."ProductToComponent" WHERE "insertedAtPrint") THEN
    RETURN NEW;
  END IF;

  v_breakdown := CASE
    WHEN jsonb_typeof(NEW."partsBreakdown") = 'array' AND jsonb_array_length(NEW."partsBreakdown") > 0
      THEN NEW."partsBreakdown"
    ELSE NULL
  END;

  WITH pieces AS (
    SELECT (e->>'productPartId')::uuid AS part_id,
           (e->>'productionJobId')::uuid AS job_id,
           GREATEST(0, COALESCE((e->>'partsAccepted')::int, 0))
             + GREATEST(0, COALESCE((e->>'partsRejected')::int, 0)) AS n
      FROM jsonb_array_elements(COALESCE(v_breakdown, '[]'::jsonb)) e
     WHERE e->>'productPartId' IS NOT NULL
       AND e->>'productionJobId' IS NOT NULL
    UNION ALL
    SELECT COALESCE(pa."productPartId", pj."productPartId"),
           pj.id,
           GREATEST(NEW."partsTotal", NEW."partsAccepted" + NEW."partsRejected", 0)
      FROM "print-farm"."PrinterAssignment" pa
      LEFT JOIN "print-farm"."ProductionJob" pj ON pj.id = pa."productionJobId"
     WHERE pa.id = NEW."assignmentId"
       AND v_breakdown IS NULL
       AND COALESCE(pa."productPartId", pj."productPartId") IS NOT NULL
  ),
  per_part AS (
    SELECT p.part_id,
           (array_agg(p.job_id) FILTER (WHERE p.job_id IS NOT NULL))[1] AS job_id,
           SUM(p.n)::int AS n
      FROM pieces p
     GROUP BY p.part_id
  )
  INSERT INTO "print-farm"."PrintInsertConsumption" (
    "id", "assignmentId", "harvestId", "productToComponentId", "productPartId",
    "itemSpecId", "productId", "productOrderId", "printerId", "odetteId",
    "harvestedAt", "piecesCount", "perPiece", "proposedQty", "createdAt", "updatedAt"
  )
  SELECT gen_random_uuid(),
         NEW."assignmentId",
         NEW.id,
         c.id,
         pp.part_id,
         c."itemSpecId",
         c."productId",
         pj."productOrderId",
         NEW."printerId",
         NEW."odetteId",
         NEW."harvestedAt",
         pp.n,
         c.quantity::double precision / GREATEST(part."quantityNeeded", 1),
         ROUND(pp.n * c.quantity::numeric / GREATEST(part."quantityNeeded", 1))::int,
         now(),
         now()
    FROM per_part pp
    JOIN "inventory"."ProductToComponent" c
      ON c."insertPartId" = pp.part_id
     AND c."insertedAtPrint"
    JOIN "inventory"."ProductPart" part ON part.id = pp.part_id
    LEFT JOIN "print-farm"."ProductionJob" pj ON pj.id = pp.job_id
    LEFT JOIN "inventory"."ProductOrder" po ON po.id = pj."productOrderId"
   WHERE c."skuId" IS NULL OR c."skuId" = po."skuId"
  ON CONFLICT ("assignmentId", "productToComponentId") DO UPDATE
     SET "harvestId"   = EXCLUDED."harvestId",
         "odetteId"    = EXCLUDED."odetteId",
         "harvestedAt" = EXCLUDED."harvestedAt",
         "piecesCount" = EXCLUDED."piecesCount",
         "perPiece"    = EXCLUDED."perPiece",
         "proposedQty" = EXCLUDED."proposedQty",
         "harvestReverted" = false,
         "updatedAt"   = now()
   WHERE "PrintInsertConsumption"."confirmedQty" IS NULL;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS pf_print_insert_from_harvest ON "print-farm"."PrinterHarvest";
CREATE TRIGGER pf_print_insert_from_harvest
  AFTER INSERT OR UPDATE OF "partsAccepted", "partsRejected", "partsTotal", "partsBreakdown", "odetteId"
  ON "print-farm"."PrinterHarvest"
  FOR EACH ROW
  EXECUTE FUNCTION "print-farm".pf_print_insert_from_harvest();

-- Annullo dello scarico: le conferme aperte spariscono (rinasceranno allo scarico
-- rifatto), quelle già fatte restano consumate e segnate «scarico annullato».
CREATE OR REPLACE FUNCTION "print-farm".pf_print_insert_on_harvest_delete()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  DELETE FROM "print-farm"."PrintInsertConsumption"
   WHERE "harvestId" = OLD.id
     AND "confirmedQty" IS NULL;
  UPDATE "print-farm"."PrintInsertConsumption"
     SET "harvestReverted" = true,
         "updatedAt" = now()
   WHERE "harvestId" = OLD.id;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS pf_print_insert_on_harvest_delete ON "print-farm"."PrinterHarvest";
CREATE TRIGGER pf_print_insert_on_harvest_delete
  BEFORE DELETE ON "print-farm"."PrinterHarvest"
  FOR EACH ROW
  EXECUTE FUNCTION "print-farm".pf_print_insert_on_harvest_delete();
