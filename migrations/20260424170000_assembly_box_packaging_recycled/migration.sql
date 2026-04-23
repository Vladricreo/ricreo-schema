-- Aggiunge il packaging terziario consumato e il flag "riciclata" alle scatole FBA.
-- - packagingItemId: Item (PACKAGING + PackagingType.class=TERTIARY) consumato alla stampa.
-- - isRecycled: true se la scatola è riciclata (dimensioni manuali in cm, nessun consumo).

ALTER TABLE "inventory"."AssemblyBox"
  ADD COLUMN IF NOT EXISTS "packagingItemId" UUID,
  ADD COLUMN IF NOT EXISTS "isRecycled" BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS "AssemblyBox_packagingItemId_idx"
  ON "inventory"."AssemblyBox" ("packagingItemId");

ALTER TABLE "inventory"."AssemblyBox"
  DROP CONSTRAINT IF EXISTS "AssemblyBox_packagingItemId_fkey";

ALTER TABLE "inventory"."AssemblyBox"
  ADD CONSTRAINT "AssemblyBox_packagingItemId_fkey"
  FOREIGN KEY ("packagingItemId") REFERENCES "inventory"."Item"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;
