-- ============================================================================
-- Scarico in una sola chiamata al DB: fondamenta (passo 2 del progetto)
-- Progetto: docs/harvest-rpc-progetto.md (§8, §9, §11, §13, §19.4, §19.5)
-- Decisione utente R-90 del 26/10/2026 (docs/operativita/99-registro-modifiche.md).
--
-- Cosa aggiunge, SENZA cambiare il comportamento del codice attuale:
--   1. PrinterHarvest."idempotencyKey" (unica) ed "effects" (jsonb).
--      La chiave si riempie dalle note JSON scritte finora da `encodeHarvestNotes`.
--   2. Indici per letture limitate:
--      - PrinterHarvest(assignmentId, harvestedAt DESC), al posto di (assignmentId);
--      - PrintRun(printerId, productionJobId, finishedAt DESC) per la serie di fallimenti.
--   3. Tabella PrinterHarvestRevert: chi ha annullato uno scarico e cosa (D-11).
--   4. CHECK sui contatori scritti solo dalla Print Farm (0 righe li violano al 26/10).
--      Esclusi di proposito OdetteContent e ProductOrderProductPart: Inventory e il
--      revert attuale scalano e poi correggono in due istruzioni, un CHECK li romperebbe.
--   5. Numero di revisione dello scarico: sequenza + trigger che chiamano solo nextval.
--      Nessuna logica nei trigger: dicono a lista scarico e TV «qualcosa è cambiato».
--      Finché il codice non legge la sequenza, non ha effetti visibili.
--
-- Non aggiunge ancora le funzioni pf_harvest_* (passi 3-5).
--
-- Applicazione: `bunx prisma migrate deploy` da client/, prima del deploy del codice.
-- È l'unica migrazione pendente al 26/10 (verificato su _prisma_migrations).
-- Tabelle toccate: PrinterHarvest 18k righe, PrintRun 22k, PrinterAssignment 52k,
-- ProductionJob 3k. Gli indici si creano in pochi secondi con lock brevi; i CHECK
-- entrano NOT VALID e poi VALIDATE (lock leggero durante la scansione).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. PrinterHarvest: chiave di idempotenza ed effetti
-- ---------------------------------------------------------------------------
ALTER TABLE "print-farm"."PrinterHarvest"
  ADD COLUMN IF NOT EXISTS "effects" JSONB,
  ADD COLUMN IF NOT EXISTS "idempotencyKey" TEXT;

-- Riempimento dalle note: `{"idempotencyKey":"<chiave>","text":"…"}`.
-- In caso di chiave ripetuta (0 casi al 26/10) la tiene solo lo scarico più vecchio,
-- così l'indice unico si crea comunque.
WITH keyed AS (
  SELECT
    id,
    substring(notes FROM '^\{"idempotencyKey":"([^"\\]+)"') AS k,
    "harvestedAt"
  FROM "print-farm"."PrinterHarvest"
  WHERE "idempotencyKey" IS NULL
    AND notes LIKE '{"idempotencyKey":"%'
),
ranked AS (
  SELECT id, k, row_number() OVER (PARTITION BY k ORDER BY "harvestedAt", id) AS rn
  FROM keyed
  WHERE k IS NOT NULL
)
UPDATE "print-farm"."PrinterHarvest" h
SET "idempotencyKey" = r.k
FROM ranked r
WHERE h.id = r.id
  AND r.rn = 1
  AND NOT EXISTS (
    SELECT 1 FROM "print-farm"."PrinterHarvest" x WHERE x."idempotencyKey" = r.k
  );

CREATE UNIQUE INDEX IF NOT EXISTS "PrinterHarvest_idempotencyKey_key"
  ON "print-farm"."PrinterHarvest"("idempotencyKey");

-- ---------------------------------------------------------------------------
-- 2. Indici per letture limitate (§19.4)
-- ---------------------------------------------------------------------------
-- Prima il nuovo, poi si toglie il vecchio: le ricerche per assignmentId restano coperte.
CREATE INDEX IF NOT EXISTS "PrinterHarvest_assignmentId_harvestedAt_idx"
  ON "print-farm"."PrinterHarvest"("assignmentId", "harvestedAt" DESC);

DROP INDEX IF EXISTS "print-farm"."PrinterHarvest_assignmentId_idx";

CREATE INDEX IF NOT EXISTS "PrintRun_printerId_productionJobId_finishedAt_idx"
  ON "print-farm"."PrintRun"("printerId", "productionJobId", "finishedAt" DESC);

-- ---------------------------------------------------------------------------
-- 3. PrinterHarvestRevert (D-11)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "print-farm"."PrinterHarvestRevert" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "harvestId" UUID NOT NULL,
    "assignmentId" UUID,
    "printerId" UUID NOT NULL,
    "revertedByUserId" INTEGER NOT NULL,
    "revertedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "source" TEXT NOT NULL DEFAULT 'HISTORY',
    "harvestedAt" TIMESTAMPTZ(6) NOT NULL,
    "harvestedByUserId" INTEGER NOT NULL,
    "partsAccepted" INTEGER NOT NULL,
    "partsRejected" INTEGER NOT NULL,
    "harvestSnapshot" JSONB NOT NULL,
    "undone" JSONB,

    CONSTRAINT "PrinterHarvestRevert_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "PrinterHarvestRevert_source_chk" CHECK ("source" IN ('HISTORY', 'VOICE'))
);

CREATE INDEX IF NOT EXISTS "PrinterHarvestRevert_printerId_revertedAt_idx"
  ON "print-farm"."PrinterHarvestRevert"("printerId", "revertedAt" DESC);
CREATE INDEX IF NOT EXISTS "PrinterHarvestRevert_harvestId_idx"
  ON "print-farm"."PrinterHarvestRevert"("harvestId");
CREATE INDEX IF NOT EXISTS "PrinterHarvestRevert_assignmentId_idx"
  ON "print-farm"."PrinterHarvestRevert"("assignmentId");
CREATE INDEX IF NOT EXISTS "PrinterHarvestRevert_revertedByUserId_idx"
  ON "print-farm"."PrinterHarvestRevert"("revertedByUserId");

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'PrinterHarvestRevert_assignmentId_fkey') THEN
    ALTER TABLE "print-farm"."PrinterHarvestRevert"
      ADD CONSTRAINT "PrinterHarvestRevert_assignmentId_fkey" FOREIGN KEY ("assignmentId")
      REFERENCES "print-farm"."PrinterAssignment"("id") ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'PrinterHarvestRevert_printerId_fkey') THEN
    ALTER TABLE "print-farm"."PrinterHarvestRevert"
      ADD CONSTRAINT "PrinterHarvestRevert_printerId_fkey" FOREIGN KEY ("printerId")
      REFERENCES "print-farm"."Printer"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'PrinterHarvestRevert_revertedByUserId_fkey') THEN
    ALTER TABLE "print-farm"."PrinterHarvestRevert"
      ADD CONSTRAINT "PrinterHarvestRevert_revertedByUserId_fkey" FOREIGN KEY ("revertedByUserId")
      REFERENCES "public"."User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
  END IF;
END $$;

-- Stessa lettura delle altre tabelle della Print Farm per il ruolo dei report, se esiste.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'planner_metriche') THEN
    GRANT SELECT ON "print-farm"."PrinterHarvestRevert" TO planner_metriche;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 4. CHECK sui contatori (§13)
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'PrinterHarvest_parts_chk') THEN
    ALTER TABLE "print-farm"."PrinterHarvest"
      ADD CONSTRAINT "PrinterHarvest_parts_chk"
      CHECK ("partsAccepted" >= 0 AND "partsRejected" >= 0
             AND "partsTotal" = "partsAccepted" + "partsRejected") NOT VALID;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'PrinterAssignment_parts_chk') THEN
    ALTER TABLE "print-farm"."PrinterAssignment"
      ADD CONSTRAINT "PrinterAssignment_parts_chk"
      CHECK ("partsProduced" >= 0 AND "partsRejected" >= 0) NOT VALID;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ProductionJob_quantities_chk') THEN
    ALTER TABLE "print-farm"."ProductionJob"
      ADD CONSTRAINT "ProductionJob_quantities_chk"
      CHECK ("quantityPrinted" >= 0 AND "quantityFailed" >= 0) NOT VALID;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'PrintRun_quantities_chk') THEN
    ALTER TABLE "print-farm"."PrintRun"
      ADD CONSTRAINT "PrintRun_quantities_chk"
      CHECK ("quantitySuccess" >= 0 AND "quantityFailed" >= 0) NOT VALID;
  END IF;
END $$;

ALTER TABLE "print-farm"."PrinterHarvest" VALIDATE CONSTRAINT "PrinterHarvest_parts_chk";
ALTER TABLE "print-farm"."PrinterAssignment" VALIDATE CONSTRAINT "PrinterAssignment_parts_chk";
ALTER TABLE "print-farm"."ProductionJob" VALIDATE CONSTRAINT "ProductionJob_quantities_chk";
ALTER TABLE "print-farm"."PrintRun" VALIDATE CONSTRAINT "PrintRun_quantities_chk";

-- ---------------------------------------------------------------------------
-- 5. Numero di revisione dello scarico (§19.5)
-- ---------------------------------------------------------------------------
-- nextval non blocca righe e non aspetta altre transazioni: nessuna contesa con il
-- backend. Una transazione annullata alza comunque il numero (al più un ricalcolo in più).
-- Lettura: SELECT last_value FROM "print-farm".harvest_rev_seq;
CREATE SEQUENCE IF NOT EXISTS "print-farm"."harvest_rev_seq";

-- Una sequenza nuova ha last_value = 1 ma is_called = false: il primo nextval
-- restituirebbe 1 e last_value non cambierebbe, quindi la prima modifica non si
-- vedrebbe. Si consuma subito il primo valore; mai setval, che su una riesecuzione
-- farebbe tornare indietro il numero.
DO $$
BEGIN
  IF NOT (SELECT is_called FROM "print-farm"."harvest_rev_seq") THEN
    PERFORM nextval('"print-farm"."harvest_rev_seq"');
  END IF;
END $$;

-- SECURITY DEFINER: chiunque possa scrivere le tabelle (app, backend, Inventory) alza
-- il numero senza bisogno di permessi sulla sequenza.
CREATE OR REPLACE FUNCTION "print-farm".pf_bump_harvest_rev()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM nextval('"print-farm"."harvest_rev_seq"');
  RETURN NULL;
END;
$$;

COMMENT ON FUNCTION "print-farm".pf_bump_harvest_rev() IS
  'Alza "print-farm".harvest_rev_seq: lista scarico e TV ricalcolano solo se è cambiato (docs/harvest-rpc-progetto.md §19.5). Nessuna logica di business.';

REVOKE ALL ON FUNCTION "print-farm".pf_bump_harvest_rev() FROM PUBLIC;

-- PrinterAssignment: solo le righe da scaricare (prima o dopo la modifica).
DROP TRIGGER IF EXISTS trg_harvest_rev_assignment_ins ON "print-farm"."PrinterAssignment";
CREATE TRIGGER trg_harvest_rev_assignment_ins
AFTER INSERT ON "print-farm"."PrinterAssignment"
FOR EACH ROW
WHEN (NEW.status::text IN ('TO_HARVEST', 'FAILED'))
EXECUTE FUNCTION "print-farm".pf_bump_harvest_rev();

DROP TRIGGER IF EXISTS trg_harvest_rev_assignment_upd ON "print-farm"."PrinterAssignment";
CREATE TRIGGER trg_harvest_rev_assignment_upd
AFTER UPDATE OF status, "partsProduced", "partsRejected", "partsExpected", "productionJobId", "printerId"
ON "print-farm"."PrinterAssignment"
FOR EACH ROW
WHEN (
  (OLD.status::text IN ('TO_HARVEST', 'FAILED') OR NEW.status::text IN ('TO_HARVEST', 'FAILED'))
  AND (OLD.status, OLD."partsProduced", OLD."partsRejected", OLD."partsExpected", OLD."productionJobId", OLD."printerId")
      IS DISTINCT FROM
      (NEW.status, NEW."partsProduced", NEW."partsRejected", NEW."partsExpected", NEW."productionJobId", NEW."printerId")
)
EXECUTE FUNCTION "print-farm".pf_bump_harvest_rev();

DROP TRIGGER IF EXISTS trg_harvest_rev_assignment_del ON "print-farm"."PrinterAssignment";
CREATE TRIGGER trg_harvest_rev_assignment_del
AFTER DELETE ON "print-farm"."PrinterAssignment"
FOR EACH ROW
WHEN (OLD.status::text IN ('TO_HARVEST', 'FAILED'))
EXECUTE FUNCTION "print-farm".pf_bump_harvest_rev();

-- Printer: piatto, stato operativo, override, posizione, nome.
DROP TRIGGER IF EXISTS trg_harvest_rev_printer_upd ON "print-farm"."Printer";
CREATE TRIGGER trg_harvest_rev_printer_upd
AFTER UPDATE OF "hasCompletedPrintOnBed", "hasCompletedPrintOnBedAssignmentId", "operationalStatus",
  "manualOverrideStatus", "locationId", "name"
ON "print-farm"."Printer"
FOR EACH ROW
WHEN (
  (OLD."hasCompletedPrintOnBed", OLD."hasCompletedPrintOnBedAssignmentId", OLD."operationalStatus",
   OLD."manualOverrideStatus", OLD."locationId", OLD."name")
  IS DISTINCT FROM
  (NEW."hasCompletedPrintOnBed", NEW."hasCompletedPrintOnBedAssignmentId", NEW."operationalStatus",
   NEW."manualOverrideStatus", NEW."locationId", NEW."name")
)
EXECUTE FUNCTION "print-farm".pf_bump_harvest_rev();

-- HarvestDraft: ogni bozza nuova o cancellata; negli aggiornamenti solo i campi veri
-- (Prisma riscrive sempre updatedAt, che non conta).
DROP TRIGGER IF EXISTS trg_harvest_rev_draft_ins_del ON "print-farm"."HarvestDraft";
CREATE TRIGGER trg_harvest_rev_draft_ins_del
AFTER INSERT OR DELETE ON "print-farm"."HarvestDraft"
FOR EACH ROW
EXECUTE FUNCTION "print-farm".pf_bump_harvest_rev();

DROP TRIGGER IF EXISTS trg_harvest_rev_draft_upd ON "print-farm"."HarvestDraft";
CREATE TRIGGER trg_harvest_rev_draft_upd
AFTER UPDATE ON "print-farm"."HarvestDraft"
FOR EACH ROW
WHEN (
  (OLD."partsAccepted", OLD."partsRejected", OLD."odetteId", OLD."odetteSource", OLD."targetLocationId",
   OLD."markOdetteFull", OLD."rejectReason", OLD."setMaintenance", OLD."note", OLD."state",
   OLD."assignmentUpdatedAt", OLD."computedSignature", OLD."aisleCode")
  IS DISTINCT FROM
  (NEW."partsAccepted", NEW."partsRejected", NEW."odetteId", NEW."odetteSource", NEW."targetLocationId",
   NEW."markOdetteFull", NEW."rejectReason", NEW."setMaintenance", NEW."note", NEW."state",
   NEW."assignmentUpdatedAt", NEW."computedSignature", NEW."aisleCode")
)
EXECUTE FUNCTION "print-farm".pf_bump_harvest_rev();

-- Odette: nuove, cancellate, cambio di stato, posizione, tipo, uso, lotto riservato, codice.
DROP TRIGGER IF EXISTS trg_harvest_rev_odette_ins_del ON inventory."Odette";
CREATE TRIGGER trg_harvest_rev_odette_ins_del
AFTER INSERT OR DELETE ON inventory."Odette"
FOR EACH ROW
EXECUTE FUNCTION "print-farm".pf_bump_harvest_rev();

DROP TRIGGER IF EXISTS trg_harvest_rev_odette_upd ON inventory."Odette";
CREATE TRIGGER trg_harvest_rev_odette_upd
AFTER UPDATE OF status, "locationId", "typeId", purpose, "reservedLotId", code
ON inventory."Odette"
FOR EACH ROW
WHEN (
  (OLD.status, OLD."locationId", OLD."typeId", OLD.purpose, OLD."reservedLotId", OLD.code)
  IS DISTINCT FROM
  (NEW.status, NEW."locationId", NEW."typeId", NEW.purpose, NEW."reservedLotId", NEW.code)
)
EXECUTE FUNCTION "print-farm".pf_bump_harvest_rev();

-- OdetteContent: quantità, parte, ordine, odetta.
DROP TRIGGER IF EXISTS trg_harvest_rev_odette_content_ins_del ON inventory."OdetteContent";
CREATE TRIGGER trg_harvest_rev_odette_content_ins_del
AFTER INSERT OR DELETE ON inventory."OdetteContent"
FOR EACH ROW
EXECUTE FUNCTION "print-farm".pf_bump_harvest_rev();

DROP TRIGGER IF EXISTS trg_harvest_rev_odette_content_upd ON inventory."OdetteContent";
CREATE TRIGGER trg_harvest_rev_odette_content_upd
AFTER UPDATE OF quantity, "PartId", "productOrderId", "odetteId"
ON inventory."OdetteContent"
FOR EACH ROW
WHEN (
  (OLD.quantity, OLD."PartId", OLD."productOrderId", OLD."odetteId")
  IS DISTINCT FROM
  (NEW.quantity, NEW."PartId", NEW."productOrderId", NEW."odetteId")
)
EXECUTE FUNCTION "print-farm".pf_bump_harvest_rev();
