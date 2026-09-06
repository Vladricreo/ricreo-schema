-- Aggiunge configurazione per-SKU del proprietario etichetta/prep FBA inbound.
-- Default NONE: la maggior parte degli SKU usa l'EAN/barcode del produttore (manufacturer barcode);
-- impostare SELLER manualmente per SKU che richiedono FNSKU del venditore, o AMAZON per FBA Label Service.

CREATE TYPE "inventory"."FbaLabelOwner" AS ENUM ('AMAZON', 'SELLER', 'NONE');
CREATE TYPE "inventory"."FbaPrepOwner" AS ENUM ('AMAZON', 'SELLER', 'NONE');

ALTER TABLE "inventory"."Sku"
  ADD COLUMN "fbaLabelOwner" "inventory"."FbaLabelOwner" NOT NULL DEFAULT 'NONE',
  ADD COLUMN "fbaPrepOwner"  "inventory"."FbaPrepOwner"  NOT NULL DEFAULT 'NONE';
