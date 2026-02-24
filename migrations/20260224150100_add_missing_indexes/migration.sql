-- Indici dichiarati nello schema Prisma ma mai tracciati in una migrazione
CREATE INDEX IF NOT EXISTS "InventoryLot_productionLotId_idx" ON "inventory"."InventoryLot"("productionLotId");
CREATE INDEX IF NOT EXISTS "OdetteContent_lotId_idx" ON "inventory"."OdetteContent"("lotId");
