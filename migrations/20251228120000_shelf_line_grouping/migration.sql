-- AlterTable
ALTER TABLE "inventory"."WarehouseShelf"
ADD COLUMN "lineCode" TEXT,
ADD COLUMN "indexInLine" INTEGER;

-- CreateIndex
CREATE INDEX "WarehouseShelf_lineCode_indexInLine_idx"
ON "inventory"."WarehouseShelf"("lineCode", "indexInLine");


