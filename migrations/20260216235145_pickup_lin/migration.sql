-- CreateEnum
CREATE TYPE "inventory"."PickingLineKind" AS ENUM ('PART_ODETTE', 'PART_STOCK', 'ITEM', 'TOOL');

-- AlterEnum
ALTER TYPE "inventory"."OdetteStatus" ADD VALUE 'FULL';

-- CreateTable
CREATE TABLE "inventory"."PickingLine" (
    "id" UUID NOT NULL,
    "assemblyOrderId" UUID NOT NULL,
    "kind" "inventory"."PickingLineKind" NOT NULL,
    "itemId" UUID,
    "productPartId" UUID,
    "odetteId" UUID,
    "requiredQty" INTEGER NOT NULL DEFAULT 0,
    "picked" BOOLEAN NOT NULL DEFAULT false,
    "pickedAt" TIMESTAMPTZ(6),
    "pickedByUserId" INTEGER,
    "originalLocationId" UUID,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PickingLine_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "PickingLine_assemblyOrderId_idx" ON "inventory"."PickingLine"("assemblyOrderId");

-- CreateIndex
CREATE INDEX "PickingLine_odetteId_idx" ON "inventory"."PickingLine"("odetteId");

-- CreateIndex
CREATE INDEX "PickingLine_itemId_idx" ON "inventory"."PickingLine"("itemId");

-- CreateIndex
CREATE INDEX "PickingLine_productPartId_idx" ON "inventory"."PickingLine"("productPartId");

-- AddForeignKey
ALTER TABLE "inventory"."PickingLine" ADD CONSTRAINT "PickingLine_assemblyOrderId_fkey" FOREIGN KEY ("assemblyOrderId") REFERENCES "inventory"."AssemblyOrder"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."PickingLine" ADD CONSTRAINT "PickingLine_itemId_fkey" FOREIGN KEY ("itemId") REFERENCES "inventory"."Item"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."PickingLine" ADD CONSTRAINT "PickingLine_productPartId_fkey" FOREIGN KEY ("productPartId") REFERENCES "inventory"."ProductPart"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."PickingLine" ADD CONSTRAINT "PickingLine_odetteId_fkey" FOREIGN KEY ("odetteId") REFERENCES "inventory"."Odette"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."PickingLine" ADD CONSTRAINT "PickingLine_pickedByUserId_fkey" FOREIGN KEY ("pickedByUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
