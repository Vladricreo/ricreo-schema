-- Modelli inbound FBA (scatole assemblate, piani SP-API, shipments, log operazioni).

CREATE TYPE "inventory"."AssemblyBoxStatus" AS ENUM (
  'ASSEMBLED',
  'RESERVED',
  'SHIPPED',
  'CANCELLED'
);

CREATE TYPE "inventory"."FbaShipmentPlanStatus" AS ENUM (
  'DRAFT',
  'PACKING',
  'PLACEMENT_PENDING',
  'PLACEMENT_CONFIRMED',
  'TRANSPORT_PENDING',
  'TRANSPORT_CONFIRMED',
  'LABELS_READY',
  'SHIPPED',
  'CANCELLED',
  'ERROR'
);

CREATE TYPE "inventory"."FbaShipmentStatus" AS ENUM (
  'PENDING',
  'WORKING',
  'SHIPPED',
  'CANCELLED',
  'ERROR'
);

CREATE TYPE "inventory"."FbaInboundOperationStatus" AS ENUM (
  'PENDING',
  'SUCCESS',
  'FAILED'
);

CREATE TABLE inventory."FbaShipmentPlan" (
  "id" UUID NOT NULL,
  "number" BIGSERIAL NOT NULL,
  "marketplaceId" TEXT NOT NULL,
  "status" "inventory"."FbaShipmentPlanStatus" NOT NULL DEFAULT 'DRAFT',
  "amazonInboundPlanId" TEXT,
  "sourceAddress" JSONB,
  "notes" TEXT,
  "placementOptionId" TEXT,
  "amazonMetadata" JSONB,
  "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "FbaShipmentPlan_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "FbaShipmentPlan_number_key" ON inventory."FbaShipmentPlan"("number");
CREATE UNIQUE INDEX "FbaShipmentPlan_amazonInboundPlanId_key" ON inventory."FbaShipmentPlan"("amazonInboundPlanId");
CREATE INDEX "FbaShipmentPlan_status_idx" ON inventory."FbaShipmentPlan"("status");
CREATE INDEX "FbaShipmentPlan_marketplaceId_idx" ON inventory."FbaShipmentPlan"("marketplaceId");

CREATE TABLE inventory."AssemblyBox" (
  "id" UUID NOT NULL,
  "code" TEXT NOT NULL,
  "number" BIGSERIAL NOT NULL,
  "assemblyOrderId" UUID NOT NULL,
  "inventoryLotId" UUID NOT NULL,
  "skuId" UUID NOT NULL,
  "quantity" INTEGER NOT NULL,
  "weightGrams" INTEGER,
  "widthMm" INTEGER,
  "heightMm" INTEGER,
  "depthMm" INTEGER,
  "status" "inventory"."AssemblyBoxStatus" NOT NULL DEFAULT 'ASSEMBLED',
  "printedAt" TIMESTAMPTZ(6),
  "qrPayload" TEXT,
  "fbaShipmentPlanId" UUID,
  "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "AssemblyBox_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "AssemblyBox_code_key" ON inventory."AssemblyBox"("code");
CREATE UNIQUE INDEX "AssemblyBox_number_key" ON inventory."AssemblyBox"("number");
CREATE INDEX "AssemblyBox_assemblyOrderId_idx" ON inventory."AssemblyBox"("assemblyOrderId");
CREATE INDEX "AssemblyBox_inventoryLotId_idx" ON inventory."AssemblyBox"("inventoryLotId");
CREATE INDEX "AssemblyBox_skuId_idx" ON inventory."AssemblyBox"("skuId");
CREATE INDEX "AssemblyBox_status_idx" ON inventory."AssemblyBox"("status");
CREATE INDEX "AssemblyBox_fbaShipmentPlanId_idx" ON inventory."AssemblyBox"("fbaShipmentPlanId");

ALTER TABLE inventory."AssemblyBox"
  ADD CONSTRAINT "AssemblyBox_assemblyOrderId_fkey"
  FOREIGN KEY ("assemblyOrderId") REFERENCES inventory."AssemblyOrder"("id")
  ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE inventory."AssemblyBox"
  ADD CONSTRAINT "AssemblyBox_inventoryLotId_fkey"
  FOREIGN KEY ("inventoryLotId") REFERENCES inventory."InventoryLot"("id")
  ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE inventory."AssemblyBox"
  ADD CONSTRAINT "AssemblyBox_skuId_fkey"
  FOREIGN KEY ("skuId") REFERENCES inventory."Sku"("id")
  ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE inventory."AssemblyBox"
  ADD CONSTRAINT "AssemblyBox_fbaShipmentPlanId_fkey"
  FOREIGN KEY ("fbaShipmentPlanId") REFERENCES inventory."FbaShipmentPlan"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

CREATE TABLE inventory."FbaShipment" (
  "id" UUID NOT NULL,
  "planId" UUID NOT NULL,
  "amazonShipmentId" TEXT,
  "destinationFulfillmentCenter" TEXT,
  "carrier" TEXT,
  "trackingNumber" TEXT,
  "bolUrl" TEXT,
  "labelDownloadUrl" TEXT,
  "status" "inventory"."FbaShipmentStatus" NOT NULL DEFAULT 'PENDING',
  "amazonPayload" JSONB,
  "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "FbaShipment_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "FbaShipment_planId_idx" ON inventory."FbaShipment"("planId");
CREATE INDEX "FbaShipment_amazonShipmentId_idx" ON inventory."FbaShipment"("amazonShipmentId");

ALTER TABLE inventory."FbaShipment"
  ADD CONSTRAINT "FbaShipment_planId_fkey"
  FOREIGN KEY ("planId") REFERENCES inventory."FbaShipmentPlan"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE inventory."FbaShipmentBox" (
  "id" UUID NOT NULL,
  "shipmentId" UUID NOT NULL,
  "assemblyBoxId" UUID NOT NULL,
  "boxIndex" INTEGER NOT NULL,
  "amazonBoxId" TEXT,
  "weightGrams" INTEGER,
  "dimensionsMm" JSONB,
  CONSTRAINT "FbaShipmentBox_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "FbaShipmentBox_shipmentId_assemblyBoxId_key"
  ON inventory."FbaShipmentBox"("shipmentId", "assemblyBoxId");
CREATE INDEX "FbaShipmentBox_assemblyBoxId_idx" ON inventory."FbaShipmentBox"("assemblyBoxId");

ALTER TABLE inventory."FbaShipmentBox"
  ADD CONSTRAINT "FbaShipmentBox_shipmentId_fkey"
  FOREIGN KEY ("shipmentId") REFERENCES inventory."FbaShipment"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE inventory."FbaShipmentBox"
  ADD CONSTRAINT "FbaShipmentBox_assemblyBoxId_fkey"
  FOREIGN KEY ("assemblyBoxId") REFERENCES inventory."AssemblyBox"("id")
  ON DELETE RESTRICT ON UPDATE CASCADE;

CREATE TABLE inventory."FbaInboundOperation" (
  "id" UUID NOT NULL,
  "planId" UUID,
  "operationId" TEXT NOT NULL,
  "operationType" TEXT NOT NULL,
  "status" "inventory"."FbaInboundOperationStatus" NOT NULL DEFAULT 'PENDING',
  "requestPayload" JSONB,
  "responsePayload" JSONB,
  "errorMessage" TEXT,
  "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "FbaInboundOperation_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "FbaInboundOperation_planId_idx" ON inventory."FbaInboundOperation"("planId");
CREATE INDEX "FbaInboundOperation_operationId_idx" ON inventory."FbaInboundOperation"("operationId");

ALTER TABLE inventory."FbaInboundOperation"
  ADD CONSTRAINT "FbaInboundOperation_planId_fkey"
  FOREIGN KEY ("planId") REFERENCES inventory."FbaShipmentPlan"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE inventory."Movement"
  ADD COLUMN "fbaShipmentPlanId" UUID,
  ADD COLUMN "assemblyBoxId" UUID;

CREATE INDEX "Movement_fbaShipmentPlanId_idx" ON inventory."Movement"("fbaShipmentPlanId");
CREATE INDEX "Movement_assemblyBoxId_idx" ON inventory."Movement"("assemblyBoxId");

ALTER TABLE inventory."Movement"
  ADD CONSTRAINT "Movement_fbaShipmentPlanId_fkey"
  FOREIGN KEY ("fbaShipmentPlanId") REFERENCES inventory."FbaShipmentPlan"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE inventory."Movement"
  ADD CONSTRAINT "Movement_assemblyBoxId_fkey"
  FOREIGN KEY ("assemblyBoxId") REFERENCES inventory."AssemblyBox"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;
