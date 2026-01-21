-- Fix: migrazione "repair" per rendere riproducibile lo storico su DB vuoti (shadow DB).
-- Motivo: `20260119120939_guide` droppa index che su un DB nuovo non esistono ancora.
-- Strategia: assicuriamo (idempotentemente) che colonne + index esistano PRIMA del DROP.
-- Nota: questa migrazione è pensata per essere marcata come "applied" in produzione (nessuna perdita dati).

-- Forza lo schema di creazione degli index (Postgres crea l'index nello schema "corrente").
SET search_path = inventory, public;

-- Assicura colonne priority (idempotente)
ALTER TABLE inventory."ProductToPackage"
  ADD COLUMN IF NOT EXISTS "priority" integer NOT NULL DEFAULT 0;

ALTER TABLE inventory."ProductToComponent"
  ADD COLUMN IF NOT EXISTS "priority" integer NOT NULL DEFAULT 0;

ALTER TABLE inventory."ProductToUtility"
  ADD COLUMN IF NOT EXISTS "priority" integer NOT NULL DEFAULT 0;

ALTER TABLE inventory."ProductPartMaterial"
  ADD COLUMN IF NOT EXISTS "priority" integer NOT NULL DEFAULT 0;

-- Assicura index priority (idempotente)
CREATE INDEX IF NOT EXISTS "ProductToPackage_productId_priority_idx"
  ON inventory."ProductToPackage" ("productId", "priority");

CREATE INDEX IF NOT EXISTS "ProductToComponent_productId_priority_idx"
  ON inventory."ProductToComponent" ("productId", "priority");

CREATE INDEX IF NOT EXISTS "ProductToUtility_productId_priority_idx"
  ON inventory."ProductToUtility" ("productId", "priority");

CREATE INDEX IF NOT EXISTS "ProductPartMaterial_productPartId_priority_idx"
  ON inventory."ProductPartMaterial" ("productPartId", "priority");

