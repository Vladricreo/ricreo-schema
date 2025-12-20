-- CreateTable
CREATE TABLE "inventory"."AmazonOrder" (
    "id" UUID NOT NULL,
    "amazonOrderId" TEXT NOT NULL,
    "marketplaceId" TEXT NOT NULL,
    "purchaseDate" TIMESTAMPTZ(6),
    "lastUpdatedDate" TIMESTAMPTZ(6),
    "orderStatus" TEXT,
    "fulfillmentChannel" TEXT,
    "salesChannel" TEXT,
    "orderChannel" TEXT,
    "isBusinessOrder" BOOLEAN DEFAULT false,
    "currency" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AmazonOrder_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."AmazonOrderItem" (
    "id" UUID NOT NULL,
    "orderId" UUID NOT NULL,
    "lineKey" TEXT NOT NULL,
    "orderItemId" TEXT,
    "sku" TEXT,
    "asin" TEXT,
    "skuId" UUID,
    "amazonProductId" UUID,
    "quantity" INTEGER,
    "itemPrice" DECIMAL(12,4),
    "itemTax" DECIMAL(12,4),
    "shippingPrice" DECIMAL(12,4),
    "shippingTax" DECIMAL(12,4),
    "itemPromotionDiscount" DECIMAL(12,4),
    "shipPromotionDiscount" DECIMAL(12,4),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AmazonOrderItem_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "AmazonOrder_purchaseDate_idx" ON "inventory"."AmazonOrder"("purchaseDate");

-- CreateIndex
CREATE INDEX "AmazonOrder_orderStatus_idx" ON "inventory"."AmazonOrder"("orderStatus");

-- CreateIndex
CREATE UNIQUE INDEX "AmazonOrder_amazonOrderId_marketplaceId_key" ON "inventory"."AmazonOrder"("amazonOrderId", "marketplaceId");

-- CreateIndex
CREATE UNIQUE INDEX "AmazonOrderItem_lineKey_key" ON "inventory"."AmazonOrderItem"("lineKey");

-- CreateIndex
CREATE INDEX "AmazonOrderItem_orderId_idx" ON "inventory"."AmazonOrderItem"("orderId");

-- CreateIndex
CREATE INDEX "AmazonOrderItem_sku_idx" ON "inventory"."AmazonOrderItem"("sku");

-- CreateIndex
CREATE INDEX "AmazonOrderItem_asin_idx" ON "inventory"."AmazonOrderItem"("asin");

-- CreateIndex
CREATE INDEX "AmazonOrderItem_skuId_idx" ON "inventory"."AmazonOrderItem"("skuId");

-- CreateIndex
CREATE INDEX "AmazonOrderItem_amazonProductId_idx" ON "inventory"."AmazonOrderItem"("amazonProductId");

-- AddForeignKey
ALTER TABLE "inventory"."AmazonOrderItem" ADD CONSTRAINT "AmazonOrderItem_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "inventory"."AmazonOrder"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."AmazonOrderItem" ADD CONSTRAINT "AmazonOrderItem_skuId_fkey" FOREIGN KEY ("skuId") REFERENCES "inventory"."Sku"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."AmazonOrderItem" ADD CONSTRAINT "AmazonOrderItem_amazonProductId_fkey" FOREIGN KEY ("amazonProductId") REFERENCES "inventory"."AmazonProduct"("id") ON DELETE SET NULL ON UPDATE CASCADE;
