-- Il tray_info_idx Bambu (es. GFL99, GFU99) identifica il TIPO di filamento,
-- non un singolo SKU. Piu' materiali (colori/brand diversi) devono poter
-- condividere lo stesso codice, altrimenti il salvataggio del secondo TPU/PLA
-- fallisce con unique constraint su bambuCode.

ALTER TABLE "print-farm"."FilamentProfile"
  DROP CONSTRAINT IF EXISTS "FilamentProfile_bambuCode_key";

DROP INDEX IF EXISTS "print-farm"."FilamentProfile_bambuCode_key";

CREATE INDEX IF NOT EXISTS "FilamentProfile_bambuCode_idx"
  ON "print-farm"."FilamentProfile" ("bambuCode");
