-- Allinea la migration history con gli indici già presenti nel database.
-- Tutti gli indici usano IF NOT EXISTS perché sono già stati creati direttamente sul DB.

-- InventoryLot: indice su productionLotId
CREATE INDEX IF NOT EXISTS "InventoryLot_productionLotId_idx" ON "inventory"."InventoryLot"("productionLotId");

-- Movement: indici composti (colonna, type)
CREATE INDEX IF NOT EXISTS "Movement_itemId_type_idx" ON "inventory"."Movement"("itemId", "type");
CREATE INDEX IF NOT EXISTS "Movement_lotId_type_idx" ON "inventory"."Movement"("lotId", "type");
CREATE INDEX IF NOT EXISTS "Movement_odetteId_type_idx" ON "inventory"."Movement"("odetteId", "type");
CREATE INDEX IF NOT EXISTS "Movement_productPartId_type_idx" ON "inventory"."Movement"("productPartId", "type");
CREATE INDEX IF NOT EXISTS "Movement_skuId_type_idx" ON "inventory"."Movement"("skuId", "type");
CREATE INDEX IF NOT EXISTS "Movement_assemblyStageId_type_idx" ON "inventory"."Movement"("assemblyStageId", "type");

-- OdetteContent: indici mancanti
CREATE INDEX IF NOT EXISTS "OdetteContent_lotId_idx" ON "inventory"."OdetteContent"("lotId");
CREATE INDEX IF NOT EXISTS "OdetteContent_inventoryLotId_idx" ON "inventory"."OdetteContent"("inventoryLotId");
