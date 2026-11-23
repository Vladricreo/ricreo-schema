-- R-278 (23/11/2026): guida di montaggio del prodotto con etichetta QR.
--
-- 1. Product.installationGuideUrl: link alla guida di montaggio per il cliente.
-- 2. Product.installationGuideStage: fase dell'assemblaggio in cui si stampa e si
--    applica l'etichetta QR «Installation guide» (FIRST_STAGE o SECOND_STAGE; null =
--    FIRST_STAGE).
-- 3. AssemblyOrder.installationGuideLabelsPrinted: etichette della guida stampate
--    per l'ordine. Nella fase della guida non si fanno entrare più pezzi di quelli
--    con l'etichetta stampata.
--
-- Additiva: colonne nullable o con default 0, nessun dato riscritto.

ALTER TABLE "inventory"."Product"
  ADD COLUMN IF NOT EXISTS "installationGuideUrl" TEXT,
  ADD COLUMN IF NOT EXISTS "installationGuideStage" "inventory"."AssemblyStageType";

ALTER TABLE "inventory"."AssemblyOrder"
  ADD COLUMN IF NOT EXISTS "installationGuideLabelsPrinted" INTEGER NOT NULL DEFAULT 0;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'Product_installationGuideStage_check'
  ) THEN
    ALTER TABLE "inventory"."Product"
      ADD CONSTRAINT "Product_installationGuideStage_check"
      CHECK ("installationGuideStage" IS NULL OR "installationGuideStage" IN ('FIRST_STAGE', 'SECOND_STAGE'));
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'AssemblyOrder_installationGuideLabelsPrinted_nonneg'
  ) THEN
    ALTER TABLE "inventory"."AssemblyOrder"
      ADD CONSTRAINT "AssemblyOrder_installationGuideLabelsPrinted_nonneg"
      CHECK ("installationGuideLabelsPrinted" >= 0);
  END IF;
END $$;

COMMENT ON COLUMN "inventory"."Product"."installationGuideUrl"
  IS 'R-278: link alla guida di montaggio per il cliente; se valorizzato si stampa un QR «Installation guide» per pezzo.';
COMMENT ON COLUMN "inventory"."Product"."installationGuideStage"
  IS 'R-278: fase in cui si stampa l''etichetta della guida (FIRST_STAGE o SECOND_STAGE; null = FIRST_STAGE).';
COMMENT ON COLUMN "inventory"."AssemblyOrder"."installationGuideLabelsPrinted"
  IS 'R-278: etichette QR della guida di montaggio stampate per l''ordine (solo crescente).';
