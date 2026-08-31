-- CreateEnum
CREATE TYPE "inventory"."SendcloudOrderStatus" AS ENUM ('TO_SHIP', 'LABEL_CREATED', 'ERROR', 'ARCHIVED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "inventory"."SendcloudMergeGroupStatus" AS ENUM ('PROPOSED', 'CONFIRMED', 'DISCARDED', 'SHIPPED');

-- AlterEnum
ALTER TYPE "inventory"."SettingsName" ADD VALUE IF NOT EXISTS 'SENDCLOUD_API_CREDENTIALS';
ALTER TYPE "inventory"."SettingsName" ADD VALUE IF NOT EXISTS 'SENDCLOUD_SYNC_DAYS';

-- CreateTable
CREATE TABLE "inventory"."SendcloudMergeGroup" (
    "id" UUID NOT NULL,
    "recipientNameHash" VARCHAR(64) NOT NULL,
    "addressHash" VARCHAR(64) NOT NULL,
    "countryCode" TEXT NOT NULL,
    "status" "inventory"."SendcloudMergeGroupStatus" NOT NULL DEFAULT 'PROPOSED',
    "createdByUserId" INTEGER,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SendcloudMergeGroup_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."SendcloudOrder" (
    "id" UUID NOT NULL,
    "sendcloudId" TEXT NOT NULL,
    "orderId" TEXT NOT NULL,
    "orderNumber" TEXT NOT NULL,
    "integrationId" INTEGER NOT NULL,
    "integrationName" TEXT,
    "marketplaceOrderId" TEXT,
    "salesChannel" "inventory"."ShipmentSalesChannel",
    "tags" TEXT[],
    "statusCode" TEXT,
    "statusMessage" TEXT,
    "recipientName" TEXT,
    "recipientNameHash" VARCHAR(64),
    "fullAddress" TEXT,
    "addressHash" VARCHAR(64),
    "email" TEXT,
    "phone" TEXT,
    "notes" TEXT,
    "countryCode" TEXT,
    "city" TEXT,
    "postalCode" TEXT,
    "postalCodePrefix" TEXT,
    "stateProvinceCode" TEXT,
    "addressJson" TEXT,
    "totalPrice" DECIMAL(12,2),
    "currency" VARCHAR(3),
    "customerShippingCost" DECIMAL(12,2),
    "weightGrams" INTEGER,
    "shippingOptionCode" TEXT,
    "shippingOptionName" TEXT,
    "contractId" INTEGER,
    "senderAddressId" INTEGER,
    "incoterm" TEXT,
    "insuredValue" DECIMAL(12,2),
    "isCashOnDelivery" BOOLEAN NOT NULL DEFAULT false,
    "localStatus" "inventory"."SendcloudOrderStatus" NOT NULL DEFAULT 'TO_SHIP',
    "addressValidation" JSONB,
    "lastError" TEXT,
    "orderCreatedAt" TIMESTAMPTZ(6),
    "syncedAt" TIMESTAMPTZ(6) NOT NULL,
    "raw" JSONB NOT NULL,
    "mergeGroupId" UUID,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SendcloudOrder_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."SendcloudOrderLine" (
    "id" UUID NOT NULL,
    "orderId" UUID NOT NULL,
    "skuCodeSnapshot" TEXT,
    "ean" TEXT,
    "name" TEXT,
    "quantity" INTEGER NOT NULL DEFAULT 1,
    "unitPrice" DECIMAL(12,2),
    "weightGrams" INTEGER,
    "remoteImageUrl" TEXT,
    "skuId" UUID,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SendcloudOrderLine_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."SendcloudParcel" (
    "id" UUID NOT NULL,
    "sendcloudParcelId" TEXT,
    "sendcloudShipmentId" TEXT,
    "carrierCode" TEXT,
    "shippingOptionCode" TEXT,
    "shippingOptionName" TEXT,
    "trackingNumber" TEXT,
    "trackingUrl" TEXT,
    "priceAmount" DECIMAL(12,2),
    "priceCurrency" VARCHAR(3),
    "weightGrams" INTEGER,
    "lengthMm" INTEGER,
    "widthMm" INTEGER,
    "heightMm" INTEGER,
    "announcementStatus" TEXT,
    "errors" JSONB,
    "labelObjectPath" TEXT,
    "shipmentId" UUID,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SendcloudParcel_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."SendcloudParcelOrder" (
    "id" UUID NOT NULL,
    "parcelId" UUID NOT NULL,
    "orderId" UUID NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SendcloudParcelOrder_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "SendcloudOrder_sendcloudId_key" ON "inventory"."SendcloudOrder"("sendcloudId");

-- CreateIndex
CREATE UNIQUE INDEX "SendcloudOrder_orderId_integrationId_key" ON "inventory"."SendcloudOrder"("orderId", "integrationId");

-- CreateIndex
CREATE INDEX "SendcloudOrder_localStatus_idx" ON "inventory"."SendcloudOrder"("localStatus");

-- CreateIndex
CREATE INDEX "SendcloudOrder_integrationId_idx" ON "inventory"."SendcloudOrder"("integrationId");

-- CreateIndex
CREATE INDEX "SendcloudOrder_countryCode_idx" ON "inventory"."SendcloudOrder"("countryCode");

-- CreateIndex
CREATE INDEX "SendcloudOrder_orderCreatedAt_idx" ON "inventory"."SendcloudOrder"("orderCreatedAt");

-- CreateIndex
CREATE INDEX "SendcloudOrder_recipientNameHash_idx" ON "inventory"."SendcloudOrder"("recipientNameHash");

-- CreateIndex
CREATE INDEX "SendcloudOrder_addressHash_idx" ON "inventory"."SendcloudOrder"("addressHash");

-- CreateIndex
CREATE INDEX "SendcloudOrder_mergeGroupId_idx" ON "inventory"."SendcloudOrder"("mergeGroupId");

-- CreateIndex
CREATE INDEX "SendcloudOrder_marketplaceOrderId_idx" ON "inventory"."SendcloudOrder"("marketplaceOrderId");

-- CreateIndex
CREATE INDEX "SendcloudOrder_salesChannel_idx" ON "inventory"."SendcloudOrder"("salesChannel");

-- CreateIndex
CREATE INDEX "SendcloudOrderLine_orderId_idx" ON "inventory"."SendcloudOrderLine"("orderId");

-- CreateIndex
CREATE INDEX "SendcloudOrderLine_skuId_idx" ON "inventory"."SendcloudOrderLine"("skuId");

-- CreateIndex
CREATE INDEX "SendcloudMergeGroup_status_idx" ON "inventory"."SendcloudMergeGroup"("status");

-- CreateIndex
CREATE INDEX "SendcloudMergeGroup_recipientNameHash_addressHash_countryCo_idx" ON "inventory"."SendcloudMergeGroup"("recipientNameHash", "addressHash", "countryCode");

-- CreateIndex
CREATE INDEX "SendcloudMergeGroup_createdByUserId_idx" ON "inventory"."SendcloudMergeGroup"("createdByUserId");

-- CreateIndex
CREATE UNIQUE INDEX "SendcloudParcel_sendcloudParcelId_key" ON "inventory"."SendcloudParcel"("sendcloudParcelId");

-- CreateIndex
CREATE INDEX "SendcloudParcel_shipmentId_idx" ON "inventory"."SendcloudParcel"("shipmentId");

-- CreateIndex
CREATE INDEX "SendcloudParcel_sendcloudShipmentId_idx" ON "inventory"."SendcloudParcel"("sendcloudShipmentId");

-- CreateIndex
CREATE INDEX "SendcloudParcel_trackingNumber_idx" ON "inventory"."SendcloudParcel"("trackingNumber");

-- CreateIndex
CREATE UNIQUE INDEX "SendcloudParcelOrder_parcelId_orderId_key" ON "inventory"."SendcloudParcelOrder"("parcelId", "orderId");

-- CreateIndex
CREATE INDEX "SendcloudParcelOrder_orderId_idx" ON "inventory"."SendcloudParcelOrder"("orderId");

-- AddForeignKey
ALTER TABLE "inventory"."SendcloudMergeGroup" ADD CONSTRAINT "SendcloudMergeGroup_createdByUserId_fkey" FOREIGN KEY ("createdByUserId") REFERENCES "public"."User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."SendcloudOrder" ADD CONSTRAINT "SendcloudOrder_mergeGroupId_fkey" FOREIGN KEY ("mergeGroupId") REFERENCES "inventory"."SendcloudMergeGroup"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."SendcloudOrderLine" ADD CONSTRAINT "SendcloudOrderLine_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "inventory"."SendcloudOrder"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."SendcloudOrderLine" ADD CONSTRAINT "SendcloudOrderLine_skuId_fkey" FOREIGN KEY ("skuId") REFERENCES "inventory"."Sku"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."SendcloudParcel" ADD CONSTRAINT "SendcloudParcel_shipmentId_fkey" FOREIGN KEY ("shipmentId") REFERENCES "inventory"."Shipment"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."SendcloudParcelOrder" ADD CONSTRAINT "SendcloudParcelOrder_parcelId_fkey" FOREIGN KEY ("parcelId") REFERENCES "inventory"."SendcloudParcel"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."SendcloudParcelOrder" ADD CONSTRAINT "SendcloudParcelOrder_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "inventory"."SendcloudOrder"("id") ON DELETE CASCADE ON UPDATE CASCADE;
