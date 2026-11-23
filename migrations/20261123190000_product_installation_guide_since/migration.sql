-- R-278 (23/11/2026): la guida di montaggio conta solo i pezzi entrati dopo la sua attivazione.
--
-- Product.installationGuideSince: da quando la guida è attiva nella fase scelta. In
-- assemblaggio le etichette servono solo per i pezzi entrati nella fase da quel momento:
-- quelli già lì quando si imposta il link non le richiedono.
--
-- La imposta il trigger, qualunque sia la strada da cui si salva il prodotto:
-- - link tolto → null;
-- - link impostato (prima non c'era) o fase cambiata → now();
-- - link cambiato con la stessa fase → resta la data di prima.
--
-- Additiva: colonna nullable; i prodotti che hanno già un link partono da adesso.

ALTER TABLE "inventory"."Product"
  ADD COLUMN IF NOT EXISTS "installationGuideSince" TIMESTAMPTZ(6);

CREATE OR REPLACE FUNCTION "inventory".product_installation_guide_since_trg()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW."installationGuideUrl" IS NULL OR btrim(NEW."installationGuideUrl") = '' THEN
    NEW."installationGuideSince" := NULL;
  ELSIF TG_OP = 'INSERT'
    OR OLD."installationGuideUrl" IS NULL
    OR btrim(OLD."installationGuideUrl") = ''
    OR COALESCE(NEW."installationGuideStage", 'FIRST_STAGE') IS DISTINCT FROM COALESCE(OLD."installationGuideStage", 'FIRST_STAGE')
  THEN
    NEW."installationGuideSince" := now();
  ELSE
    NEW."installationGuideSince" := COALESCE(OLD."installationGuideSince", now());
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS "Product_installation_guide_since" ON "inventory"."Product";
CREATE TRIGGER "Product_installation_guide_since"
BEFORE INSERT OR UPDATE OF "installationGuideUrl", "installationGuideStage", "installationGuideSince"
ON "inventory"."Product"
FOR EACH ROW
EXECUTE FUNCTION "inventory".product_installation_guide_since_trg();

UPDATE "inventory"."Product"
SET "installationGuideSince" = now()
WHERE "installationGuideUrl" IS NOT NULL
  AND btrim("installationGuideUrl") <> ''
  AND "installationGuideSince" IS NULL;

COMMENT ON COLUMN "inventory"."Product"."installationGuideSince"
  IS 'R-278: da quando la guida di montaggio è attiva nella fase scelta (trigger); le etichette servono solo per i pezzi entrati nella fase da allora.';
