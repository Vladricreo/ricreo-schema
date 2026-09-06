-- Piani parti versionati per prodotto ("ProductPartPlan").
--
-- Permette di cambiare la composizione in parti di un prodotto (es. da multi-parte a mono-parte,
-- oppure MAKE -> BUY) senza rompere gli ordini gia esistenti:
--   • si crea un nuovo piano ACTIVE e il precedente passa a DEPLETED
--   • ProductOrder / AssemblyOrder congelano il piano usato (productPartPlanId)
--   • ProductPart appartiene a un piano (planId)
--
-- Idempotente: enum con guard pg_type, tabelle/colonne con IF NOT EXISTS, FK con guard pg_constraint.

-- ─── 1) Enum ProductPartPlanStatus ─────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type t
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'inventory'
      AND t.typname = 'ProductPartPlanStatus'
  ) THEN
    CREATE TYPE "inventory"."ProductPartPlanStatus" AS ENUM ('DRAFT', 'ACTIVE', 'DEPLETED');
  END IF;
END $$;

-- ─── 2) Tabella ProductPartPlan ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS "inventory"."ProductPartPlan" (
  "id"             UUID           NOT NULL DEFAULT gen_random_uuid(),
  "productId"      UUID           NOT NULL,
  "name"           TEXT,
  "revisionNumber" INTEGER        NOT NULL DEFAULT 1,
  "status"         "inventory"."ProductPartPlanStatus" NOT NULL DEFAULT 'ACTIVE',
  "effectiveFrom"  TIMESTAMPTZ(6) NOT NULL DEFAULT NOW(),
  "depletedAt"     TIMESTAMPTZ(6),
  "createdAt"      TIMESTAMPTZ(6) NOT NULL DEFAULT NOW(),
  "updatedAt"      TIMESTAMPTZ(6) NOT NULL DEFAULT NOW(),

  CONSTRAINT "ProductPartPlan_pkey" PRIMARY KEY ("id")
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'ProductPartPlan_productId_fkey'
  ) THEN
    ALTER TABLE "inventory"."ProductPartPlan"
      ADD CONSTRAINT "ProductPartPlan_productId_fkey"
      FOREIGN KEY ("productId") REFERENCES "inventory"."Product"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS "ProductPartPlan_productId_status_effectiveFrom_idx"
  ON "inventory"."ProductPartPlan"("productId", "status", "effectiveFrom");
CREATE INDEX IF NOT EXISTS "ProductPartPlan_productId_idx"
  ON "inventory"."ProductPartPlan"("productId");

COMMENT ON TABLE "inventory"."ProductPartPlan"
  IS 'Revisione datata della composizione in parti di un prodotto. Un piano ACTIVE per prodotto, gli altri DEPLETED/DRAFT.';

-- ─── 3) ProductPart.planId ─────────────────────────────────────────────────
ALTER TABLE "inventory"."ProductPart"
  ADD COLUMN IF NOT EXISTS "planId" UUID;

COMMENT ON COLUMN "inventory"."ProductPart"."planId"
  IS 'Piano parti (revisione) a cui appartiene la parte. NULL solo per righe legacy prima del backfill.';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'ProductPart_planId_fkey'
  ) THEN
    ALTER TABLE "inventory"."ProductPart"
      ADD CONSTRAINT "ProductPart_planId_fkey"
      FOREIGN KEY ("planId") REFERENCES "inventory"."ProductPartPlan"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS "ProductPart_planId_idx"
  ON "inventory"."ProductPart"("planId");

-- ─── 4) ProductOrder.productPartPlanId ─────────────────────────────────────
ALTER TABLE "inventory"."ProductOrder"
  ADD COLUMN IF NOT EXISTS "productPartPlanId" UUID;

COMMENT ON COLUMN "inventory"."ProductOrder"."productPartPlanId"
  IS 'Piano parti congelato alla creazione dell''ordine di produzione (composizione storica).';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'ProductOrder_productPartPlanId_fkey'
  ) THEN
    ALTER TABLE "inventory"."ProductOrder"
      ADD CONSTRAINT "ProductOrder_productPartPlanId_fkey"
      FOREIGN KEY ("productPartPlanId") REFERENCES "inventory"."ProductPartPlan"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS "ProductOrder_productPartPlanId_idx"
  ON "inventory"."ProductOrder"("productPartPlanId");

-- ─── 5) AssemblyOrder.productPartPlanId ────────────────────────────────────
ALTER TABLE "inventory"."AssemblyOrder"
  ADD COLUMN IF NOT EXISTS "productPartPlanId" UUID;

COMMENT ON COLUMN "inventory"."AssemblyOrder"."productPartPlanId"
  IS 'Piano parti congelato alla creazione dell''ordine di assemblaggio (ereditato dai ProductOrder collegati).';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'AssemblyOrder_productPartPlanId_fkey'
  ) THEN
    ALTER TABLE "inventory"."AssemblyOrder"
      ADD CONSTRAINT "AssemblyOrder_productPartPlanId_fkey"
      FOREIGN KEY ("productPartPlanId") REFERENCES "inventory"."ProductPartPlan"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS "AssemblyOrder_productPartPlanId_idx"
  ON "inventory"."AssemblyOrder"("productPartPlanId");

-- ─── 6) Backfill: un piano ACTIVE iniziale per ogni prodotto ───────────────
-- Crea il piano iniziale solo per i prodotti che non ne hanno ancora uno.
INSERT INTO "inventory"."ProductPartPlan"
  ("id", "productId", "name", "revisionNumber", "status", "effectiveFrom", "createdAt", "updatedAt")
SELECT gen_random_uuid(), p."id", 'Piano iniziale', 1, 'ACTIVE', NOW(), NOW(), NOW()
FROM "inventory"."Product" p
WHERE NOT EXISTS (
  SELECT 1 FROM "inventory"."ProductPartPlan" pp WHERE pp."productId" = p."id"
);

-- Assegna tutte le parti esistenti al piano attivo del rispettivo prodotto.
UPDATE "inventory"."ProductPart" pt
SET "planId" = (
  SELECT pp."id"
  FROM "inventory"."ProductPartPlan" pp
  WHERE pp."productId" = pt."productId" AND pp."status" = 'ACTIVE'
  ORDER BY pp."effectiveFrom" DESC
  LIMIT 1
)
WHERE pt."planId" IS NULL;

-- Congela il piano attivo sugli ordini di produzione esistenti.
UPDATE "inventory"."ProductOrder" po
SET "productPartPlanId" = (
  SELECT pp."id"
  FROM "inventory"."ProductPartPlan" pp
  WHERE pp."productId" = po."productId" AND pp."status" = 'ACTIVE'
  ORDER BY pp."effectiveFrom" DESC
  LIMIT 1
)
WHERE po."productPartPlanId" IS NULL;

-- Congela il piano attivo sugli ordini di assemblaggio esistenti.
UPDATE "inventory"."AssemblyOrder" ao
SET "productPartPlanId" = (
  SELECT pp."id"
  FROM "inventory"."ProductPartPlan" pp
  WHERE pp."productId" = ao."productId" AND pp."status" = 'ACTIVE'
  ORDER BY pp."effectiveFrom" DESC
  LIMIT 1
)
WHERE ao."productPartPlanId" IS NULL;
