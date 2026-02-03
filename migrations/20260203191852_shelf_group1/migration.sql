/*
  Warnings:

  - A unique constraint covering the columns `[groupId,positionInGroup]` on the table `WarehouseShelf` will be added. If there are existing duplicate values, this will fail.

*/
-- CreateIndex
CREATE UNIQUE INDEX "WarehouseShelf_groupId_positionInGroup_key" ON "inventory"."WarehouseShelf"("groupId", "positionInGroup");

-- CreateIndex
CREATE INDEX "WarehouseShelfGroup_code_idx" ON "inventory"."WarehouseShelfGroup"("code");

-- CreateIndex
CREATE INDEX "WarehouseShelfGroup_order_idx" ON "inventory"."WarehouseShelfGroup"("order");
