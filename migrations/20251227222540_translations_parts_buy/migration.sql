-- CreateEnum
CREATE TYPE "inventory"."PartSourceType" AS ENUM ('MAKE', 'BUY');

-- AlterTable
ALTER TABLE "inventory"."InventoryLot" ADD COLUMN     "productPartId" UUID;

-- AlterTable
ALTER TABLE "inventory"."ProductPart" ADD COLUMN     "sourceType" "inventory"."PartSourceType" NOT NULL DEFAULT 'MAKE',
ADD COLUMN     "supplierId" UUID;

-- AlterTable
ALTER TABLE "inventory"."PurchaseOrderLine" ADD COLUMN     "productPartId" UUID,
ALTER COLUMN "itemId" DROP NOT NULL;

-- CreateTable
CREATE TABLE "inventory"."GuideTranslation" (
    "id" UUID NOT NULL,
    "guideId" UUID NOT NULL,
    "language" VARCHAR(10) NOT NULL,
    "sourceHash" VARCHAR(64) NOT NULL,
    "translatedTitle" TEXT NOT NULL,
    "translatedDescription" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "GuideTranslation_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."WarningTranslation" (
    "id" UUID NOT NULL,
    "warningId" UUID NOT NULL,
    "language" VARCHAR(10) NOT NULL,
    "sourceHash" VARCHAR(64) NOT NULL,
    "translatedDescription" TEXT NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "WarningTranslation_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "GuideTranslation_guideId_idx" ON "inventory"."GuideTranslation"("guideId");

-- CreateIndex
CREATE INDEX "GuideTranslation_language_idx" ON "inventory"."GuideTranslation"("language");

-- CreateIndex
CREATE UNIQUE INDEX "GuideTranslation_guideId_language_key" ON "inventory"."GuideTranslation"("guideId", "language");

-- CreateIndex
CREATE INDEX "WarningTranslation_warningId_idx" ON "inventory"."WarningTranslation"("warningId");

-- CreateIndex
CREATE INDEX "WarningTranslation_language_idx" ON "inventory"."WarningTranslation"("language");

-- CreateIndex
CREATE UNIQUE INDEX "WarningTranslation_warningId_language_key" ON "inventory"."WarningTranslation"("warningId", "language");

-- CreateIndex
CREATE INDEX "InventoryLot_productPartId_idx" ON "inventory"."InventoryLot"("productPartId");

-- CreateIndex
CREATE INDEX "ProductPart_supplierId_idx" ON "inventory"."ProductPart"("supplierId");

-- CreateIndex
CREATE INDEX "PurchaseOrderLine_productPartId_idx" ON "inventory"."PurchaseOrderLine"("productPartId");

-- AddForeignKey
ALTER TABLE "inventory"."ProductPart" ADD CONSTRAINT "ProductPart_supplierId_fkey" FOREIGN KEY ("supplierId") REFERENCES "inventory"."Supplier"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."GuideTranslation" ADD CONSTRAINT "GuideTranslation_guideId_fkey" FOREIGN KEY ("guideId") REFERENCES "inventory"."Guide"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."WarningTranslation" ADD CONSTRAINT "WarningTranslation_warningId_fkey" FOREIGN KEY ("warningId") REFERENCES "inventory"."Warning"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."InventoryLot" ADD CONSTRAINT "InventoryLot_productPartId_fkey" FOREIGN KEY ("productPartId") REFERENCES "inventory"."ProductPart"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."PurchaseOrderLine" ADD CONSTRAINT "PurchaseOrderLine_productPartId_fkey" FOREIGN KEY ("productPartId") REFERENCES "inventory"."ProductPart"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
