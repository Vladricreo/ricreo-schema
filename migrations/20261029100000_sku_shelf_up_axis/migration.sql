-- ============================================================================
-- Lato a terra dei pacchi sugli scaffali (28/10/2026).
--
-- Quale misura del pacco (Sku.dimensions) sta in verticale sullo scaffale.
-- NULL = automatico: la pagina «Dimensioni scaffali» usa il verso che fa
-- stare più pacchi nella sezione.
-- ============================================================================

CREATE TYPE "inventory"."BoxUpAxis" AS ENUM ('WIDTH', 'DEPTH', 'HEIGHT');

ALTER TABLE "inventory"."Sku" ADD COLUMN "shelfUpAxis" "inventory"."BoxUpAxis";
