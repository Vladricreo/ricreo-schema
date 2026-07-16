-- Indici strategici per il picker filamenti (wizard runout / compatible-spools).
-- Obiettivo: accelerare i filtri su spool parziali, inventario MATERIAL e assignment attivi.

-- FilamentSpool: join su item + lookup montate + pool ACTIVE non montate
CREATE INDEX IF NOT EXISTS "FilamentSpool_itemId_idx"
  ON "print-farm"."FilamentSpool"("itemId");

CREATE INDEX IF NOT EXISTS "FilamentSpool_mountedOnId_idx"
  ON "print-farm"."FilamentSpool"("mountedOnId");

CREATE INDEX IF NOT EXISTS "FilamentSpool_status_mountedOnId_remainingWeight_idx"
  ON "print-farm"."FilamentSpool"("status", "mountedOnId", "remainingWeight");

-- PrinterAssignment: assignment attivi per stampante (compatible-spools / host checks)
CREATE INDEX IF NOT EXISTS "PrinterAssignment_printerId_status_idx"
  ON "print-farm"."PrinterAssignment"("printerId", "status");

-- Item: inventario materiali con stock
CREATE INDEX IF NOT EXISTS "Item_type_inStock_idx"
  ON "inventory"."Item"("type", "inStock");

-- Color: matching hex dal firmware / AMS
CREATE INDEX IF NOT EXISTS "Color_hexCode_idx"
  ON "inventory"."Color"("hexCode");
