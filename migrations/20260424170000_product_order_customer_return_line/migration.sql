-- Collega ProductOrder alla riga reso che ha generato l'ordine (parti mancanti).
ALTER TABLE inventory."ProductOrder"
  ADD COLUMN IF NOT EXISTS "customerReturnLineId" UUID;

CREATE INDEX IF NOT EXISTS "ProductOrder_customerReturnLineId_idx"
  ON inventory."ProductOrder" ("customerReturnLineId");

ALTER TABLE inventory."ProductOrder"
  ADD CONSTRAINT "ProductOrder_customerReturnLineId_fkey"
  FOREIGN KEY ("customerReturnLineId")
  REFERENCES inventory."CustomerReturnLine" ("id")
  ON DELETE SET NULL
  ON UPDATE CASCADE;
