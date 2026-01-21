-- Aggiunge un `id` UUID alle tabelle di join prodotto (componenti / packaging / utility)
-- in modo compatibile con DB già popolati (produzione).
--
-- Nota: Prisma non può aggiungere una colonna REQUIRED con default "prisma-level"
-- quando esistono righe. Qui usiamo un default DB-level (`gen_random_uuid()`)
-- e backfilliamo le righe esistenti prima di imporre NOT NULL / PK.

-- ProductToComponent
ALTER TABLE inventory."ProductToComponent"
  ADD COLUMN IF NOT EXISTS "id" uuid;

UPDATE inventory."ProductToComponent"
SET "id" = gen_random_uuid()
WHERE "id" IS NULL;

ALTER TABLE inventory."ProductToComponent"
  ALTER COLUMN "id" SET DEFAULT gen_random_uuid(),
  ALTER COLUMN "id" SET NOT NULL;

ALTER TABLE inventory."ProductToComponent"
  DROP CONSTRAINT IF EXISTS "ProductToComponent_pkey";

ALTER TABLE inventory."ProductToComponent"
  ADD CONSTRAINT "ProductToComponent_pkey" PRIMARY KEY ("id");

-- ProductToPackage
ALTER TABLE inventory."ProductToPackage"
  ADD COLUMN IF NOT EXISTS "id" uuid;

UPDATE inventory."ProductToPackage"
SET "id" = gen_random_uuid()
WHERE "id" IS NULL;

ALTER TABLE inventory."ProductToPackage"
  ALTER COLUMN "id" SET DEFAULT gen_random_uuid(),
  ALTER COLUMN "id" SET NOT NULL;

ALTER TABLE inventory."ProductToPackage"
  DROP CONSTRAINT IF EXISTS "ProductToPackage_pkey";

ALTER TABLE inventory."ProductToPackage"
  ADD CONSTRAINT "ProductToPackage_pkey" PRIMARY KEY ("id");

-- ProductToUtility
ALTER TABLE inventory."ProductToUtility"
  ADD COLUMN IF NOT EXISTS "id" uuid;

UPDATE inventory."ProductToUtility"
SET "id" = gen_random_uuid()
WHERE "id" IS NULL;

ALTER TABLE inventory."ProductToUtility"
  ALTER COLUMN "id" SET DEFAULT gen_random_uuid(),
  ALTER COLUMN "id" SET NOT NULL;

ALTER TABLE inventory."ProductToUtility"
  DROP CONSTRAINT IF EXISTS "ProductToUtility_pkey";

ALTER TABLE inventory."ProductToUtility"
  ADD CONSTRAINT "ProductToUtility_pkey" PRIMARY KEY ("id");

