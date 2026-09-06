-- Corridoio: codice condiviso tra file e scaffali senza fila accessibili dallo stesso passaggio.

-- AlterTable
ALTER TABLE "inventory"."WarehouseShelfGroup" ADD COLUMN "aisleCode" TEXT;

-- CreateIndex
CREATE INDEX "WarehouseShelfGroup_aisleCode_idx" ON "inventory"."WarehouseShelfGroup"("aisleCode");

-- AlterTable
ALTER TABLE "inventory"."WarehouseShelf" ADD COLUMN "aisleCode" TEXT;

-- CreateIndex
CREATE INDEX "WarehouseShelf_aisleCode_idx" ON "inventory"."WarehouseShelf"("aisleCode");
