-- Variante "usata" di un ricambio: SKU con suffisso _USED collegata al ricambio nuovo di base.
--
-- Permette di avere stock separati (es. 2 hotend nuovi + 2 hotend usati) come due Item distinti,
-- mantenendo un collegamento esplicito tramite Item.baseItemId.
--
-- Additiva e idempotente: ADD COLUMN IF NOT EXISTS + constraint guardato da DO block.

ALTER TABLE "inventory"."Item"
  ADD COLUMN IF NOT EXISTS "baseItemId" UUID;

COMMENT ON COLUMN "inventory"."Item"."baseItemId"
  IS 'Per le varianti usate (_USED): id del ricambio nuovo di base.';

CREATE INDEX IF NOT EXISTS "Item_baseItemId_idx"
  ON "inventory"."Item" ("baseItemId");

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'Item_baseItemId_fkey'
  ) THEN
    ALTER TABLE "inventory"."Item"
      ADD CONSTRAINT "Item_baseItemId_fkey"
      FOREIGN KEY ("baseItemId") REFERENCES "inventory"."Item"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END
$$;
