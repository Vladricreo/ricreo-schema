-- Storico riempimento odette: snapshot pezzi/categoria/operatore quando l'odette
-- diventa FULL a DB (dopo lo scarico, non al click "Segna piena").

CREATE TABLE IF NOT EXISTS "inventory"."OdetteFillHistory" (
  "id"                 UUID NOT NULL DEFAULT gen_random_uuid(),
  "odetteId"           UUID NOT NULL,
  "odetteCode"         TEXT NOT NULL,
  "odetteTypeId"       UUID,
  "odetteTypeName"     TEXT,
  "categoryId"         UUID,
  "categoryName"       TEXT,
  "pieceCount"         INTEGER NOT NULL,
  "partId"             UUID,
  "partName"           TEXT,
  "markedFullAt"       TIMESTAMPTZ(6) NOT NULL DEFAULT now(),
  "markedFullByUserId" INTEGER,
  "source"             TEXT NOT NULL DEFAULT 'HARVEST',
  "createdAt"          TIMESTAMPTZ(6) NOT NULL DEFAULT now(),
  CONSTRAINT "OdetteFillHistory_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "OdetteFillHistory_categoryId_markedFullAt_idx"
  ON "inventory"."OdetteFillHistory" ("categoryId", "markedFullAt");
CREATE INDEX IF NOT EXISTS "OdetteFillHistory_odetteTypeId_markedFullAt_idx"
  ON "inventory"."OdetteFillHistory" ("odetteTypeId", "markedFullAt");
CREATE INDEX IF NOT EXISTS "OdetteFillHistory_odetteId_idx"
  ON "inventory"."OdetteFillHistory" ("odetteId");
CREATE INDEX IF NOT EXISTS "OdetteFillHistory_markedFullByUserId_idx"
  ON "inventory"."OdetteFillHistory" ("markedFullByUserId");
CREATE INDEX IF NOT EXISTS "OdetteFillHistory_markedFullAt_idx"
  ON "inventory"."OdetteFillHistory" ("markedFullAt");

COMMENT ON TABLE "inventory"."OdetteFillHistory"
  IS 'Snapshot riempimento odette: pezzi, categoria e operatore quando diventa FULL a DB.';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'OdetteFillHistory_odetteId_fkey'
  ) THEN
    ALTER TABLE "inventory"."OdetteFillHistory"
      ADD CONSTRAINT "OdetteFillHistory_odetteId_fkey"
      FOREIGN KEY ("odetteId") REFERENCES "inventory"."Odette"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'OdetteFillHistory_odetteTypeId_fkey'
  ) THEN
    ALTER TABLE "inventory"."OdetteFillHistory"
      ADD CONSTRAINT "OdetteFillHistory_odetteTypeId_fkey"
      FOREIGN KEY ("odetteTypeId") REFERENCES "inventory"."OdetteType"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'OdetteFillHistory_categoryId_fkey'
  ) THEN
    ALTER TABLE "inventory"."OdetteFillHistory"
      ADD CONSTRAINT "OdetteFillHistory_categoryId_fkey"
      FOREIGN KEY ("categoryId") REFERENCES "inventory"."Category"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'OdetteFillHistory_partId_fkey'
  ) THEN
    ALTER TABLE "inventory"."OdetteFillHistory"
      ADD CONSTRAINT "OdetteFillHistory_partId_fkey"
      FOREIGN KEY ("partId") REFERENCES "inventory"."ProductPart"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'OdetteFillHistory_markedFullByUserId_fkey'
  ) THEN
    ALTER TABLE "inventory"."OdetteFillHistory"
      ADD CONSTRAINT "OdetteFillHistory_markedFullByUserId_fkey"
      FOREIGN KEY ("markedFullByUserId") REFERENCES "public"."User"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END
$$;
