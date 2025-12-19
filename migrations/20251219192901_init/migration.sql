-- CreateSchema
CREATE SCHEMA IF NOT EXISTS "inventory";

-- CreateSchema
CREATE SCHEMA IF NOT EXISTS "print-farm";

-- CreateEnum
CREATE TYPE "inventory"."ItemType" AS ENUM ('MATERIAL', 'PACKAGING', 'COMPONENT', 'ACCESSORY', 'SPARE_PART', 'TOOL', 'UTILITY', 'PRODUCT', 'ODETTE');

-- CreateEnum
CREATE TYPE "inventory"."AssemblyStageType" AS ENUM ('RAW', 'ASSEMBLED', 'FIRST_STAGE', 'SECOND_STAGE', 'OTHER');

-- CreateEnum
CREATE TYPE "inventory"."PackagingClass" AS ENUM ('PRIMARY', 'SECONDARY', 'OTHERS');

-- CreateEnum
CREATE TYPE "inventory"."WarningType" AS ENUM ('SAFETY', 'HANDLING', 'ASSEMBLY', 'QUALITY', 'OTHER');

-- CreateEnum
CREATE TYPE "inventory"."WarningSeverity" AS ENUM ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL');

-- CreateEnum
CREATE TYPE "inventory"."WarehouseRowType" AS ENUM ('PRINTER', 'ITEM', 'PRODUCT_FBA', 'PRODUCT_FBM', 'PRODUCT_CUSTOM', 'ODETTE_ASSEMBLED', 'ODETTE_UNLOAD', 'MIXED');

-- CreateEnum
CREATE TYPE "inventory"."WarehouseLocationKind" AS ENUM ('SLOT', 'PRINTER_SLOT', 'ODETTE_HEAD', 'ODETTE_EMPTY_STORAGE', 'ODETTE_PRINT_FARM_QUEUE', 'ODETTE_ASSEMBLY_BUFFER', 'ODETTE_FULL_STORAGE', 'MATERIAL_SHELF', 'BUFFER', 'ASSEMBLY');

-- CreateEnum
CREATE TYPE "inventory"."LotInspectionResult" AS ENUM ('PASSED', 'FAILED', 'REWORK', 'BLOCKED');

-- CreateEnum
CREATE TYPE "inventory"."MovementType" AS ENUM ('USO', 'ACQUISTO', 'VENDITA', 'STAGE_IN', 'STAGE_OUT', 'PRODUZIONE', 'RIMBORSO_PRODUZIONE', 'RIMBORSO_USO', 'TRASH', 'CORRECTION_UP', 'CORRECTION_DOWN');

-- CreateEnum
CREATE TYPE "inventory"."InventoryChannel" AS ENUM ('UNALLOCATED', 'FBM', 'FBA', 'CUSTOM');

-- CreateEnum
CREATE TYPE "inventory"."InventoryLotOriginType" AS ENUM ('PURCHASE', 'PRODUCTION', 'ADJUSTMENT', 'OTHER');

-- CreateEnum
CREATE TYPE "inventory"."InventoryLotStatus" AS ENUM ('OPEN', 'CLOSED');

-- CreateEnum
CREATE TYPE "print-farm"."MaintenanceType" AS ENUM ('ROUTINE', 'REPAIR', 'UPGRADE', 'CALIBRATION', 'OTHER');

-- CreateEnum
CREATE TYPE "print-farm"."PrinterIssueSource" AS ENUM ('MQTT', 'WSS', 'OPERATOR', 'SCHEDULER');

-- CreateEnum
CREATE TYPE "print-farm"."PrinterIssueCategory" AS ENUM ('FILAMENT', 'BED', 'PRINT', 'NETWORK', 'MAINTENANCE', 'SAFETY', 'OTHER');

-- CreateEnum
CREATE TYPE "print-farm"."PrinterIssueStatus" AS ENUM ('OPEN', 'ACKED', 'RESOLVED');

-- CreateEnum
CREATE TYPE "print-farm"."FailureReason" AS ENUM ('BED_ADHESION', 'NOZZLE_CLOG', 'FILAMENT_ISSUE', 'LAYER_SHIFT', 'POWER_LOSS', 'SPAGHETTI', 'QUALITY_ISSUE', 'USER_ERROR', 'SLICING_ERROR', 'OTHER');

-- CreateEnum
CREATE TYPE "print-farm"."FeedbackType" AS ENUM ('PRINTER_ISSUE', 'FILE_ISSUE', 'SLICING_IMPROVEMENT', 'MODIFICATION_REQUEST', 'GENERAL');

-- CreateEnum
CREATE TYPE "print-farm"."FeedbackStatus" AS ENUM ('OPEN', 'IN_PROGRESS', 'RESOLVED', 'WONT_FIX');

-- CreateEnum
CREATE TYPE "print-farm"."FeedbackPriority" AS ENUM ('LOW', 'NORMAL', 'HIGH', 'URGENT');

-- CreateEnum
CREATE TYPE "print-farm"."SpoolStatus" AS ENUM ('ACTIVE', 'DEPLETED', 'ARCHIVED');

-- CreateEnum
CREATE TYPE "print-farm"."ErrorSeverity" AS ENUM ('WARNING', 'CRITICAL');

-- CreateEnum
CREATE TYPE "print-farm"."ErrorType" AS ENUM ('HMS', 'PRINTING');

-- CreateEnum
CREATE TYPE "print-farm"."SettingsType" AS ENUM ('PRINTER', 'TOTAL_AVAILABLE_POWER', 'COST_PER_KWH', 'WORKHOURS', 'WORKDAYS', 'USER', 'GENERAL');

-- CreateEnum
CREATE TYPE "print-farm"."FarmProductionStatus" AS ENUM ('READY_TO_PRODUCE', 'NEEDS_CONFIGURATION', 'AWAITING_RESOURCES', 'IN_PROGRESS', 'COMPLETED', 'FAILED');

-- CreateEnum
CREATE TYPE "print-farm"."PrintRunStatus" AS ENUM ('PENDING', 'IN_PROGRESS', 'COMPLETED', 'FAILED');

-- CreateEnum
CREATE TYPE "print-farm"."PrinterStatus" AS ENUM ('FINISH', 'RUNNING', 'IDLE', 'OFFLINE', 'PAUSE', 'PREPARE', 'FAILED', 'SLICING', 'ERROR');

-- CreateEnum
CREATE TYPE "print-farm"."PrinterOperationalStatus" AS ENUM ('AVAILABLE', 'QUEUED', 'TO_LOAD', 'TO_HARVEST', 'FILAMENT_SWAP_NEEDED', 'ERROR');

-- CreateEnum
CREATE TYPE "print-farm"."PrinterManualOverrideStatus" AS ENUM ('MAINTENANCE', 'DISABLED');

-- CreateEnum
CREATE TYPE "print-farm"."AssignmentStatus" AS ENUM ('QUEUED', 'READY', 'TO_LOAD', 'PRINTING', 'COMPLETED', 'UNLOADED', 'FAILED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "print-farm"."SoftwareType" AS ENUM ('BAMBU_STUDIO', 'MAINSAIL');

-- CreateEnum
CREATE TYPE "print-farm"."PrinterBrand" AS ENUM ('BAMBU_LAB', 'KLIPPER', 'PRUSA');

-- CreateEnum
CREATE TYPE "print-farm"."FileStatus" AS ENUM ('DRAFT', 'TESTING', 'APPROVED', 'ARCHIVED', 'REJECTED');

-- CreateEnum
CREATE TYPE "inventory"."AssemblyOperationType" AS ENUM ('PICKING', 'ASSEMBLY', 'PRIMARY_PACKAGING', 'SECONDARY_PACKAGING', 'ALLOCATION');

-- CreateEnum
CREATE TYPE "inventory"."ProductionStatus" AS ENUM ('READY_TO_PRODUCE', 'PRODUCED', 'PRODUCING', 'CANCELLED', 'NEED_SUPPLIES');

-- CreateEnum
CREATE TYPE "inventory"."AssemblyStatus" AS ENUM ('READY_TO_ASSEMBLE', 'NEEDS_PARTS', 'ASSEMBLY_STARTED', 'PARTIALLY_COMPLETED', 'ASSEMBLY_COMPLETED', 'ON_HOLD', 'CANCELLED');

-- CreateEnum
CREATE TYPE "inventory"."OdetteStatus" AS ENUM ('IN_USE', 'RESERVED', 'EMPTY', 'OUT_OF_SERVICE');

-- CreateEnum
CREATE TYPE "inventory"."OdettePurpose" AS ENUM ('PRODUCTS', 'ITEMS');

-- CreateEnum
CREATE TYPE "inventory"."OdetteLocationKind" AS ENUM ('EMPTY_STORAGE', 'PRINT_FARM_QUEUE', 'ASSEMBLY_BUFFER', 'FULL_STORAGE');

-- CreateEnum
CREATE TYPE "inventory"."OdetteAssignmentRole" AS ENUM ('SOURCE', 'DESTINATION');

-- CreateEnum
CREATE TYPE "inventory"."OrderStatus" AS ENUM ('TO_ORDER', 'ORDERED', 'RECEIVED');

-- CreateEnum
CREATE TYPE "inventory"."FulfillmentType" AS ENUM ('FBA', 'FBM', 'OTHER');

-- CreateEnum
CREATE TYPE "inventory"."ListingStatus" AS ENUM ('ACTIVE', 'INACTIVE', 'INCOMPLETE');

-- CreateEnum
CREATE TYPE "inventory"."RestockAction" AS ENUM ('NOW', 'SOON', 'NO');

-- CreateEnum
CREATE TYPE "inventory"."AmazonOrderStatus" AS ENUM ('TO_ORDER', 'PROCESSING', 'PRODUCED', 'SHIPPED');

-- CreateEnum
CREATE TYPE "inventory"."ShipmentLabelStatus" AS ENUM ('PENDING', 'GENERATED', 'PRINTED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "inventory"."ShipmentType" AS ENUM ('PRIME', 'BUSINESS', 'STANDARD');

-- CreateEnum
CREATE TYPE "inventory"."Marketplace" AS ENUM ('GENERIC', 'AMAZON_FBA', 'AMAZON_FBM', 'EBAY', 'ETSY');

-- CreateEnum
CREATE TYPE "inventory"."SettingsName" AS ENUM ('PROFIT_MARGIN', 'LABOR_COST', 'THEME', 'LANGUAGE', 'VAT_RATE', 'STOCK_THRESHOLD', 'AMAZON_RESTOCK_TIME', 'AMAZON_OPTIMAL_STOCK_DAYS', 'FBM_OPTIMAL_STOCK_DAYS', 'PRODUCTION_ORDER_AUTOMATION', 'AMAZON_ORDER_FIXED_COST', 'AMAZON_STORAGE_FEE_LOW', 'AMAZON_STORAGE_FEE_HIGH');

-- CreateTable
CREATE TABLE "Profile" (
    "id" SERIAL NOT NULL,
    "bio" TEXT,
    "avatarUrl" TEXT,
    "language" TEXT DEFAULT 'it',
    "userId" INTEGER NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Profile_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "User" (
    "id" SERIAL NOT NULL,
    "email" TEXT NOT NULL,
    "username" TEXT NOT NULL,
    "password" TEXT NOT NULL,
    "name" TEXT,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "User_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Role" (
    "id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Role_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "UserRole" (
    "userId" INTEGER NOT NULL,
    "roleId" UUID NOT NULL,
    "assignedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "UserRole_pkey" PRIMARY KEY ("userId","roleId")
);

-- CreateTable
CREATE TABLE "Permission" (
    "id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "resource" TEXT NOT NULL,
    "action" TEXT NOT NULL,
    "description" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Permission_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "RolePermission" (
    "roleId" UUID NOT NULL,
    "permissionId" UUID NOT NULL,

    CONSTRAINT "RolePermission_pkey" PRIMARY KEY ("roleId","permissionId")
);

-- CreateTable
CREATE TABLE "Post" (
    "id" SERIAL NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "title" VARCHAR(255) NOT NULL,
    "content" TEXT,
    "published" BOOLEAN NOT NULL DEFAULT false,
    "authorId" INTEGER NOT NULL,

    CONSTRAINT "Post_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."Item" (
    "id" UUID NOT NULL,
    "imageUrl" TEXT,
    "name" TEXT NOT NULL,
    "sku" TEXT NOT NULL,
    "price" DECIMAL(12,4) NOT NULL,
    "weight" DECIMAL(12,3),
    "type" "inventory"."ItemType" NOT NULL,
    "categoryId" UUID,
    "colorId" UUID,
    "brandId" UUID,
    "supplierId" UUID,
    "locationId" UUID,
    "standardWeightId" UUID,
    "dimensionsId" UUID,
    "properties" JSONB,
    "inStock" INTEGER NOT NULL DEFAULT 0,
    "reserved" INTEGER NOT NULL DEFAULT 0,
    "onOrder" INTEGER NOT NULL DEFAULT 0,
    "minStock" INTEGER NOT NULL DEFAULT 0,
    "maxStock" INTEGER NOT NULL DEFAULT 0,
    "minOrder" INTEGER NOT NULL DEFAULT 0,
    "maxOrder" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "packagingTypeId" UUID,

    CONSTRAINT "Item_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."Product" (
    "id" UUID NOT NULL,
    "imageUrl" TEXT,
    "treemfUrl" TEXT,
    "name" TEXT NOT NULL,
    "asin" TEXT,
    "ean" TEXT,
    "cost" DECIMAL(12,4) NOT NULL DEFAULT 0,
    "estimatedPrice" DECIMAL(12,4),
    "sellingPrice" DECIMAL(12,4),
    "profitMargin" DECIMAL(5,4),
    "laborCost" DECIMAL(12,4),
    "laborMinutes" DECIMAL(8,2),
    "dimensionsId" UUID,
    "itemId" UUID,
    "properties" JSONB,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "minStock" INTEGER NOT NULL DEFAULT 5,
    "minOrder" INTEGER NOT NULL DEFAULT 0,
    "averageDailySales" DECIMAL(12,4),
    "suggestedMinStock" INTEGER,
    "autoAdjustMinStock" BOOLEAN NOT NULL DEFAULT false,
    "lastSalesCalculation" TIMESTAMPTZ(6),

    CONSTRAINT "Product_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."ProductPart" (
    "id" UUID NOT NULL,
    "imageUrl" TEXT,
    "name" TEXT NOT NULL,
    "price" DECIMAL(12,4),
    "weight" DECIMAL(12,3) NOT NULL DEFAULT 0,
    "properties" JSONB,
    "productId" UUID NOT NULL,
    "quantityNeeded" INTEGER NOT NULL DEFAULT 0,
    "dimensionsId" UUID,
    "inStock" INTEGER NOT NULL DEFAULT 0,
    "onOrder" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "ProductPart_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."Dimensions" (
    "id" UUID NOT NULL,
    "width" DECIMAL(12,3) NOT NULL DEFAULT 0,
    "height" DECIMAL(12,3) NOT NULL DEFAULT 0,
    "depth" DECIMAL(12,3) NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Dimensions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."AssemblyStage" (
    "id" UUID NOT NULL,
    "imageUrl" TEXT,
    "name" TEXT NOT NULL,
    "productId" UUID NOT NULL,
    "order" INTEGER DEFAULT 0,
    "instock" INTEGER DEFAULT 0,
    "description" TEXT,
    "assemblyTime" INTEGER NOT NULL DEFAULT 0,
    "type" "inventory"."AssemblyStageType" NOT NULL DEFAULT 'ASSEMBLED',
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AssemblyStage_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."Guide" (
    "id" UUID NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT,
    "url" TEXT,
    "imageUrl" TEXT,
    "fileUrl" TEXT,
    "order" INTEGER NOT NULL DEFAULT 0,
    "appliesToAll" BOOLEAN NOT NULL DEFAULT true,
    "isnew" BOOLEAN NOT NULL DEFAULT false,
    "productId" UUID NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Guide_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."GuideToAssemblyStage" (
    "guideId" UUID NOT NULL,
    "assemblyStageId" UUID NOT NULL,

    CONSTRAINT "GuideToAssemblyStage_pkey" PRIMARY KEY ("guideId","assemblyStageId")
);

-- CreateTable
CREATE TABLE "inventory"."Warning" (
    "id" UUID NOT NULL,
    "type" "inventory"."WarningType" NOT NULL DEFAULT 'OTHER',
    "severity" "inventory"."WarningSeverity" NOT NULL DEFAULT 'MEDIUM',
    "description" TEXT NOT NULL,
    "imageUrl" TEXT,
    "order" INTEGER NOT NULL DEFAULT 0,
    "appliesToAll" BOOLEAN NOT NULL DEFAULT true,
    "isnew" BOOLEAN NOT NULL DEFAULT false,
    "productId" UUID NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Warning_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."WarningToAssemblyStage" (
    "warningId" UUID NOT NULL,
    "assemblyStageId" UUID NOT NULL,

    CONSTRAINT "WarningToAssemblyStage_pkey" PRIMARY KEY ("warningId","assemblyStageId")
);

-- CreateTable
CREATE TABLE "inventory"."Category" (
    "id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "associatedItemType" "inventory"."ItemType" NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Category_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."PackagingType" (
    "id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "class" "inventory"."PackagingClass" NOT NULL DEFAULT 'PRIMARY',
    "associatedItemType" "inventory"."ItemType" NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PackagingType_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."Color" (
    "id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "hexCode" TEXT,
    "associatedItemType" "inventory"."ItemType" NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Color_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."Brand" (
    "id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "associatedItemType" "inventory"."ItemType" NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Brand_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."StandardWeight" (
    "id" UUID NOT NULL,
    "weight" DECIMAL(12,3) NOT NULL,
    "associatedItemType" "inventory"."ItemType" NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "StandardWeight_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."CompatibleMachine" (
    "id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "associatedItemType" "inventory"."ItemType" NOT NULL DEFAULT 'SPARE_PART',
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CompatibleMachine_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."ProductToPackage" (
    "productId" UUID NOT NULL,
    "itemId" UUID NOT NULL,
    "quantity" INTEGER NOT NULL DEFAULT 1,

    CONSTRAINT "ProductToPackage_pkey" PRIMARY KEY ("productId","itemId")
);

-- CreateTable
CREATE TABLE "inventory"."ProductToTool" (
    "productId" UUID NOT NULL,
    "itemId" UUID NOT NULL,

    CONSTRAINT "ProductToTool_pkey" PRIMARY KEY ("productId","itemId")
);

-- CreateTable
CREATE TABLE "inventory"."ProductToUtility" (
    "productId" UUID NOT NULL,
    "itemId" UUID NOT NULL,
    "quantity" INTEGER NOT NULL DEFAULT 1,
    "assemblyStageId" UUID,

    CONSTRAINT "ProductToUtility_pkey" PRIMARY KEY ("productId","itemId")
);

-- CreateTable
CREATE TABLE "inventory"."ProductToComponent" (
    "productId" UUID NOT NULL,
    "itemId" UUID NOT NULL,
    "quantity" INTEGER NOT NULL DEFAULT 1,

    CONSTRAINT "ProductToComponent_pkey" PRIMARY KEY ("productId","itemId")
);

-- CreateTable
CREATE TABLE "inventory"."Movement" (
    "id" UUID NOT NULL,
    "itemId" UUID,
    "quantity" INTEGER NOT NULL,
    "type" "inventory"."MovementType" NOT NULL,
    "date" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "productId" UUID,
    "assemblyStageId" UUID,
    "productPartId" UUID,
    "channel" "inventory"."InventoryChannel",
    "skuId" UUID,
    "odetteId" UUID,
    "lotId" UUID,

    CONSTRAINT "Movement_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."InventoryLot" (
    "id" UUID NOT NULL,
    "number" BIGSERIAL NOT NULL,
    "code" TEXT NOT NULL,
    "originType" "inventory"."InventoryLotOriginType" NOT NULL,
    "initialQuantity" INTEGER NOT NULL,
    "status" "inventory"."InventoryLotStatus" NOT NULL DEFAULT 'OPEN',
    "itemId" UUID,
    "productId" UUID,
    "purchaseOrderLineId" UUID,
    "supplierId" UUID,
    "supplierLotCode" TEXT,
    "productItemOrderId" UUID,
    "assemblyOrderId" UUID,
    "productionLotId" UUID,
    "manufacturedAt" TIMESTAMPTZ(6),
    "receivedAt" TIMESTAMPTZ(6),
    "expiryDate" TIMESTAMPTZ(6),
    "note" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "InventoryLot_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."WarehouseShelf" (
    "id" UUID NOT NULL,
    "code" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT,
    "imageUrl" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "WarehouseShelf_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."WarehouseRow" (
    "id" UUID NOT NULL,
    "code" TEXT NOT NULL,
    "description" TEXT,
    "shelfId" UUID,
    "orderInShelf" INTEGER,
    "rowType" "inventory"."WarehouseRowType" NOT NULL DEFAULT 'MIXED',
    "itemType" "inventory"."ItemType",
    "categoryId" UUID,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "WarehouseRow_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."WarehouseLocation" (
    "id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "rowId" UUID,
    "positionInRow" INTEGER,
    "kind" "inventory"."WarehouseLocationKind" NOT NULL DEFAULT 'SLOT',
    "associatedItemType" "inventory"."ItemType",
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "WarehouseLocation_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."WarehouseItemAllocation" (
    "id" UUID NOT NULL,
    "locationId" UUID NOT NULL,
    "itemId" UUID NOT NULL,
    "quantity" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "WarehouseItemAllocation_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."WarehouseSkuAllocation" (
    "id" UUID NOT NULL,
    "locationId" UUID NOT NULL,
    "skuId" UUID NOT NULL,
    "quantity" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "WarehouseSkuAllocation_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."LotInspection" (
    "id" UUID NOT NULL,
    "lotId" UUID NOT NULL,
    "inspectedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "inspectedBy" INTEGER,
    "result" "inventory"."LotInspectionResult" NOT NULL,
    "notes" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "LotInspection_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."FinishedAllocation" (
    "id" UUID NOT NULL,
    "productItemId" UUID NOT NULL,
    "assemblyStageId" UUID,
    "channel" "inventory"."InventoryChannel" NOT NULL,
    "quantity" INTEGER NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "skuId" UUID,

    CONSTRAINT "FinishedAllocation_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "print-farm"."PrinterMaintenanceLog" (
    "id" UUID NOT NULL,
    "number" BIGSERIAL NOT NULL,
    "printerId" UUID NOT NULL,
    "type" "print-farm"."MaintenanceType" NOT NULL DEFAULT 'ROUTINE',
    "description" TEXT NOT NULL,
    "performedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "performedBy" TEXT,
    "cost" DECIMAL(12,2),
    "durationMin" INTEGER,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PrinterMaintenanceLog_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "print-farm"."PrinterIssue" (
    "id" UUID NOT NULL,
    "number" BIGSERIAL NOT NULL,
    "printerId" UUID NOT NULL,
    "assignmentId" UUID,
    "source" "print-farm"."PrinterIssueSource" NOT NULL DEFAULT 'MQTT',
    "category" "print-farm"."PrinterIssueCategory" NOT NULL,
    "status" "print-farm"."PrinterIssueStatus" NOT NULL DEFAULT 'OPEN',
    "severity" "print-farm"."ErrorSeverity" NOT NULL DEFAULT 'WARNING',
    "errorCodeId" INTEGER,
    "externalCode" TEXT,
    "message" TEXT,
    "openedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lastSeenAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "acknowledgedAt" TIMESTAMPTZ(6),
    "acknowledgedBy" TEXT,
    "resolvedAt" TIMESTAMPTZ(6),
    "resolvedBy" TEXT,
    "metadata" JSONB,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PrinterIssue_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "print-farm"."PrintFailureLog" (
    "id" UUID NOT NULL,
    "number" BIGSERIAL NOT NULL,
    "productionJobId" UUID NOT NULL,
    "printerId" UUID NOT NULL,
    "printRunId" UUID,
    "quantityScrapped" INTEGER NOT NULL DEFAULT 1,
    "reason" "print-farm"."FailureReason" NOT NULL DEFAULT 'OTHER',
    "notes" TEXT,
    "reportedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "reportedBy" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PrintFailureLog_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "print-farm"."FarmFeedback" (
    "id" UUID NOT NULL,
    "number" BIGSERIAL NOT NULL,
    "type" "print-farm"."FeedbackType" NOT NULL DEFAULT 'GENERAL',
    "priority" "print-farm"."FeedbackPriority" NOT NULL DEFAULT 'NORMAL',
    "status" "print-farm"."FeedbackStatus" NOT NULL DEFAULT 'OPEN',
    "description" TEXT NOT NULL,
    "printerId" UUID,
    "fileId" UUID,
    "reportedBy" TEXT,
    "resolvedBy" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "FarmFeedback_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "print-farm"."FilamentProfile" (
    "id" UUID NOT NULL,
    "itemId" UUID NOT NULL,
    "bambuCode" TEXT,
    "printTempMin" INTEGER,
    "printTempMax" INTEGER,
    "bedTempMin" INTEGER,
    "bedTempMax" INTEGER,
    "dryingTemp" INTEGER,
    "dryingTimeHours" INTEGER,
    "density" DECIMAL(5,3),
    "diameter" DECIMAL(4,2) NOT NULL DEFAULT 1.75,
    "compatibleNozzles" TEXT[],
    "maxVolumetricSpeed" DECIMAL(6,2),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "FilamentProfile_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "print-farm"."FilamentSpool" (
    "id" UUID NOT NULL,
    "itemId" UUID NOT NULL,
    "initialWeight" DECIMAL(10,3) NOT NULL,
    "remainingWeight" DECIMAL(10,3) NOT NULL,
    "isVirtual" BOOLEAN NOT NULL DEFAULT true,
    "status" "print-farm"."SpoolStatus" NOT NULL DEFAULT 'ACTIVE',
    "lotCode" TEXT,
    "inventoryLotId" UUID,
    "nfcTagId" TEXT,
    "openedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "finishedAt" TIMESTAMPTZ(6),
    "mountedOnId" UUID,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "FilamentSpool_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "print-farm"."ProjectThreeMFFile" (
    "id" UUID NOT NULL,
    "filename" TEXT NOT NULL,
    "filepath" TEXT NOT NULL,
    "filesize" DECIMAL(12,3) NOT NULL,
    "projectName" TEXT NOT NULL,
    "imageUrl" TEXT NOT NULL DEFAULT '',
    "estimatedDurationMinutes" INTEGER NOT NULL,
    "compatiblePrinters" TEXT[],
    "zHeight" DECIMAL(12,3) NOT NULL,
    "nozzleDiameter" DECIMAL(4,2) NOT NULL,
    "partCount" INTEGER NOT NULL,
    "totalLayers" INTEGER NOT NULL,
    "totalFilamentWeight" DECIMAL(12,3),
    "plateNumber" INTEGER NOT NULL DEFAULT 1,
    "plateFillPercentage" DECIMAL(3,2) NOT NULL DEFAULT 0.70,
    "version" INTEGER NOT NULL DEFAULT 1,
    "status" "print-farm"."FileStatus" NOT NULL DEFAULT 'DRAFT',
    "changeLog" TEXT,
    "previousVersionId" UUID,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "productId" UUID,

    CONSTRAINT "ProjectThreeMFFile_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "print-farm"."ProjectFileMaterial" (
    "id" UUID NOT NULL,
    "fileId" UUID NOT NULL,
    "materialId" UUID NOT NULL,
    "usedWeight" DECIMAL(12,3) NOT NULL,
    "colorUsed" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ProjectFileMaterial_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "print-farm"."ProjectPart" (
    "id" UUID NOT NULL,
    "quantity" INTEGER NOT NULL DEFAULT 0,
    "weight" DECIMAL(12,3),
    "imageFromFileUrl" TEXT,
    "productPartId" UUID,
    "productId" UUID,
    "fileId" UUID NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ProjectPart_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "print-farm"."ProductionJob" (
    "id" UUID NOT NULL,
    "number" BIGSERIAL NOT NULL,
    "priority" INTEGER NOT NULL DEFAULT 1,
    "assignedPrinterIds" TEXT[],
    "estimatedTime" DECIMAL(12,2),
    "eta" TIMESTAMPTZ(6),
    "startedAt" TIMESTAMPTZ(6),
    "finishedAt" TIMESTAMPTZ(6),
    "status" "print-farm"."FarmProductionStatus" NOT NULL DEFAULT 'READY_TO_PRODUCE',
    "quantity" INTEGER NOT NULL,
    "quantityPrinted" INTEGER NOT NULL DEFAULT 0,
    "quantityFailed" INTEGER NOT NULL DEFAULT 0,
    "notes" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "productId" UUID,
    "productPartId" UUID,
    "productOrderId" UUID,
    "assemblyOrderId" UUID,
    "productionLotId" UUID,
    "powerConsumed" DECIMAL(12,3),

    CONSTRAINT "ProductionJob_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "print-farm"."PrintRun" (
    "id" UUID NOT NULL,
    "number" BIGSERIAL NOT NULL,
    "startedAt" TIMESTAMPTZ(6),
    "finishedAt" TIMESTAMPTZ(6),
    "assignmentId" UUID,
    "productionJobId" UUID,
    "fileId" UUID NOT NULL,
    "printTimeMinutes" DECIMAL(12,2),
    "powerConsumed" DECIMAL(12,3),
    "energyCostSnapshot" DECIMAL(12,4),
    "quantitySuccess" INTEGER NOT NULL DEFAULT 0,
    "quantityFailed" INTEGER NOT NULL DEFAULT 0,
    "status" "print-farm"."PrintRunStatus" NOT NULL DEFAULT 'PENDING',
    "spoolId" UUID,
    "notes" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PrintRun_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "print-farm"."Printer" (
    "id" UUID NOT NULL,
    "serial" TEXT,
    "name" TEXT NOT NULL,
    "brand" "print-farm"."PrinterBrand" NOT NULL DEFAULT 'BAMBU_LAB',
    "modelId" INTEGER NOT NULL,
    "imageUrl" TEXT,
    "ipAddress" TEXT,
    "softwareType" "print-farm"."SoftwareType" NOT NULL DEFAULT 'BAMBU_STUDIO',
    "accessCode" TEXT,
    "apiKey" TEXT,
    "peakPower" DECIMAL(12,2),
    "runPower" DECIMAL(12,2),
    "nozzleDiameter" DECIMAL(4,2) NOT NULL DEFAULT 0.4,
    "nozzleType" TEXT NOT NULL DEFAULT 'Hardened Steel',
    "structure" TEXT NOT NULL DEFAULT 'CoreXY',
    "ams" BOOLEAN,
    "pushAllTimeout" INTEGER,
    "status" "print-farm"."PrinterStatus" NOT NULL DEFAULT 'OFFLINE',
    "operationalStatus" "print-farm"."PrinterOperationalStatus" NOT NULL DEFAULT 'AVAILABLE',
    "lastWssAt" TIMESTAMPTZ(6),
    "lastMqttAt" TIMESTAMPTZ(6),
    "manualOverrideStatus" "print-farm"."PrinterManualOverrideStatus",
    "manualOverrideReason" TEXT,
    "manualOverrideBy" TEXT,
    "manualOverrideAt" TIMESTAMPTZ(6),
    "bedOccupied" BOOLEAN NOT NULL DEFAULT false,
    "bedOccupiedAt" TIMESTAMPTZ(6),
    "bedOccupiedAssignmentId" UUID,
    "locationId" UUID,
    "currentMaterialId" UUID,
    "currentSpoolId" UUID,
    "preferredTags" TEXT[],
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Printer_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "print-farm"."PrinterModel" (
    "id" SERIAL NOT NULL,
    "name" TEXT NOT NULL,
    "deviceModel" TEXT NOT NULL,
    "buildPlateWidth" DECIMAL(8,2),
    "buildPlateDepth" DECIMAL(8,2),
    "buildPlateHeight" DECIMAL(8,2),

    CONSTRAINT "PrinterModel_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "print-farm"."PrinterMacro" (
    "id" SERIAL NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "gcode" JSONB NOT NULL,
    "printerCompatibility" TEXT[],
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PrinterMacro_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "print-farm"."ErrorCode" (
    "id" SERIAL NOT NULL,
    "code" TEXT NOT NULL,
    "description" TEXT,
    "solutions" TEXT[],
    "skipthiserror" BOOLEAN NOT NULL DEFAULT false,
    "severity" "print-farm"."ErrorSeverity" NOT NULL DEFAULT 'WARNING',
    "errorType" "print-farm"."ErrorType" NOT NULL DEFAULT 'HMS',
    "action" TEXT,
    "guideUrl" TEXT,
    "qrCodeUrl" TEXT,
    "qrCodeData" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ErrorCode_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "print-farm"."PrinterLogs" (
    "id" SERIAL NOT NULL,
    "printerId" UUID NOT NULL,
    "errorCodeId" INTEGER NOT NULL,
    "occurredAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "fixedAt" TIMESTAMPTZ(6),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PrinterLogs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "print-farm"."Settings" (
    "id" SERIAL NOT NULL,
    "settings" JSONB NOT NULL,
    "settingsname" TEXT NOT NULL,
    "settingstype" "print-farm"."SettingsType" NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Settings_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "print-farm"."PrinterAssignment" (
    "id" UUID NOT NULL,
    "number" BIGSERIAL NOT NULL,
    "productionJobId" UUID NOT NULL,
    "printerId" UUID NOT NULL,
    "queuePosition" INTEGER NOT NULL DEFAULT 0,
    "status" "print-farm"."AssignmentStatus" NOT NULL DEFAULT 'QUEUED',
    "scheduledAt" TIMESTAMPTZ(6),
    "startedAt" TIMESTAMPTZ(6),
    "completedAt" TIMESTAMPTZ(6),
    "printsExpected" INTEGER NOT NULL,
    "printsCompleted" INTEGER NOT NULL DEFAULT 0,
    "partsExpected" INTEGER NOT NULL,
    "partsProduced" INTEGER NOT NULL DEFAULT 0,
    "partsRejected" INTEGER NOT NULL DEFAULT 0,
    "materialRequired" TEXT,
    "colorRequired" TEXT,
    "materialChanged" BOOLEAN NOT NULL DEFAULT false,
    "materialChangedAt" TIMESTAMPTZ(6),
    "notes" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PrinterAssignment_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "print-farm"."PrinterHarvest" (
    "id" UUID NOT NULL,
    "assignmentId" UUID NOT NULL,
    "printerId" UUID NOT NULL,
    "odetteId" UUID NOT NULL,
    "harvestedByUserId" INTEGER NOT NULL,
    "harvestedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "partsAccepted" INTEGER NOT NULL DEFAULT 0,
    "partsRejected" INTEGER NOT NULL DEFAULT 0,
    "partsTotal" INTEGER NOT NULL DEFAULT 0,
    "rejectReason" TEXT,
    "notes" TEXT,
    "imageUrl" TEXT,
    "productionLotId" UUID,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PrinterHarvest_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "print-farm"."PrinterFilamentLoad" (
    "id" UUID NOT NULL,
    "assignmentId" UUID,
    "printerId" UUID NOT NULL,
    "loadedByUserId" INTEGER NOT NULL,
    "loadedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "spoolId" UUID,
    "previousMaterial" TEXT,
    "newMaterial" TEXT,
    "newColor" TEXT,
    "confirmed" BOOLEAN NOT NULL DEFAULT false,
    "confirmedAt" TIMESTAMPTZ(6),
    "notes" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PrinterFilamentLoad_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."ProductOrder" (
    "id" UUID NOT NULL,
    "number" BIGSERIAL NOT NULL,
    "productId" UUID NOT NULL,
    "skuId" UUID,
    "quantityToProduce" INTEGER NOT NULL,
    "quantityProduced" INTEGER NOT NULL DEFAULT 0,
    "eta" TIMESTAMPTZ(6),
    "finishedAt" TIMESTAMPTZ(6),
    "cost" DECIMAL(12,4),
    "priority" INTEGER NOT NULL DEFAULT 1,
    "productionStatus" "inventory"."ProductionStatus" NOT NULL DEFAULT 'READY_TO_PRODUCE',
    "status" "inventory"."OrderStatus" NOT NULL DEFAULT 'TO_ORDER',
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "producedByUserId" INTEGER,
    "assemblyOrderId" UUID,

    CONSTRAINT "ProductOrder_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."ProductOrderItem" (
    "productOrderId" UUID NOT NULL,
    "itemId" UUID NOT NULL,
    "quantity" INTEGER NOT NULL DEFAULT 1,

    CONSTRAINT "ProductOrderItem_pkey" PRIMARY KEY ("productOrderId","itemId")
);

-- CreateTable
CREATE TABLE "inventory"."ProductOrderProductPart" (
    "productOrderId" UUID NOT NULL,
    "productPartId" UUID NOT NULL,
    "quantity" INTEGER NOT NULL DEFAULT 1,
    "quantityProduced" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "ProductOrderProductPart_pkey" PRIMARY KEY ("productOrderId","productPartId")
);

-- CreateTable
CREATE TABLE "inventory"."AssemblyOrder" (
    "id" UUID NOT NULL,
    "number" BIGSERIAL NOT NULL,
    "productId" UUID NOT NULL,
    "skuId" UUID NOT NULL,
    "quantityToAssemble" INTEGER NOT NULL DEFAULT 0,
    "quantityAssembled" INTEGER NOT NULL DEFAULT 0,
    "quantityScrapped" INTEGER NOT NULL DEFAULT 0,
    "startedAt" TIMESTAMPTZ(6),
    "finishedAt" TIMESTAMPTZ(6),
    "priority" INTEGER NOT NULL DEFAULT 0,
    "status" "inventory"."AssemblyStatus" NOT NULL DEFAULT 'READY_TO_ASSEMBLE',
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "assembledByUserId" INTEGER,

    CONSTRAINT "AssemblyOrder_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."AssemblyOperation" (
    "id" UUID NOT NULL,
    "assemblyOrderId" UUID NOT NULL,
    "type" "inventory"."AssemblyOperationType" NOT NULL,
    "assemblyStageId" UUID,
    "operatorId" INTEGER NOT NULL,
    "startedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "endedAt" TIMESTAMPTZ(6),
    "durationSeconds" INTEGER,
    "quantityInput" INTEGER NOT NULL DEFAULT 0,
    "quantityProduced" INTEGER NOT NULL DEFAULT 0,
    "quantityScrapped" INTEGER NOT NULL DEFAULT 0,
    "lotId" UUID,
    "notes" TEXT,
    "metadata" JSONB,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AssemblyOperation_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."ProductionLot" (
    "id" UUID NOT NULL,
    "number" BIGSERIAL NOT NULL,
    "code" TEXT NOT NULL,
    "printerId" TEXT,
    "material" TEXT,
    "color" TEXT,
    "startedAt" TIMESTAMPTZ(6),
    "finishedAt" TIMESTAMPTZ(6),
    "note" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ProductionLot_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."Odette" (
    "id" UUID NOT NULL,
    "code" TEXT NOT NULL,
    "barcode" TEXT,
    "status" "inventory"."OdetteStatus" NOT NULL DEFAULT 'EMPTY',
    "purpose" "inventory"."OdettePurpose" NOT NULL DEFAULT 'PRODUCTS',
    "lockedStage" "inventory"."AssemblyStageType",
    "typeId" UUID,
    "locationId" UUID,
    "reservedLotId" UUID,
    "reservedAt" TIMESTAMPTZ(6),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Odette_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."OdetteContent" (
    "id" UUID NOT NULL,
    "odetteId" UUID NOT NULL,
    "itemId" UUID,
    "PartId" UUID,
    "assemblyStageId" UUID,
    "quantity" INTEGER NOT NULL,
    "skuId" UUID,
    "lotId" UUID,
    "inventoryLotId" UUID,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "OdetteContent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."OdetteReservation" (
    "id" UUID NOT NULL,
    "odetteId" UUID NOT NULL,
    "odetteContentId" UUID NOT NULL,
    "assemblyOrderId" UUID,
    "channel" "inventory"."InventoryChannel",
    "skuId" UUID,
    "reservedQty" INTEGER NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "OdetteReservation_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."OdetteMove" (
    "id" UUID NOT NULL,
    "odetteId" UUID NOT NULL,
    "fromLocationId" UUID,
    "toLocationId" UUID,
    "movedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "movedByUser" INTEGER,
    "note" TEXT,

    CONSTRAINT "OdetteMove_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."OdetteCleaningLog" (
    "id" UUID NOT NULL,
    "odetteId" UUID NOT NULL,
    "note" TEXT,
    "at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "byUserId" INTEGER,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "OdetteCleaningLog_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."OdetteType" (
    "id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "code" TEXT,
    "imageUrl" TEXT,
    "purpose" "inventory"."OdettePurpose" NOT NULL DEFAULT 'PRODUCTS',
    "categoryId" UUID,
    "dimensionsId" UUID,
    "internalVolumeCm3" INTEGER,
    "maxWeightKg" DECIMAL(10,2),
    "maxPieces" INTEGER,
    "stackable" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "OdetteType_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."OdetteLocationPreference" (
    "id" UUID NOT NULL,
    "locationId" UUID NOT NULL,
    "kind" "inventory"."OdetteLocationKind" NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "OdetteLocationPreference_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."OdetteAssemblyAssignment" (
    "id" UUID NOT NULL,
    "odetteId" UUID NOT NULL,
    "assemblyOrderId" UUID NOT NULL,
    "stage" "inventory"."AssemblyStageType" NOT NULL,
    "role" "inventory"."OdetteAssignmentRole" NOT NULL,
    "allocatedQuantity" INTEGER NOT NULL DEFAULT 0,
    "notes" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "OdetteAssemblyAssignment_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."PurchaseOrder" (
    "id" UUID NOT NULL,
    "number" BIGSERIAL NOT NULL,
    "supplierId" UUID NOT NULL,
    "status" "inventory"."OrderStatus" NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "orderedAt" TIMESTAMPTZ(6),
    "receivedAt" TIMESTAMPTZ(6),
    "shippingCost" DECIMAL(12,4),
    "customsDuty" DECIMAL(12,4),

    CONSTRAINT "PurchaseOrder_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."PurchaseOrderLine" (
    "id" UUID NOT NULL,
    "number" BIGSERIAL NOT NULL,
    "orderId" UUID NOT NULL,
    "itemId" UUID NOT NULL,
    "quantity" INTEGER NOT NULL,
    "pricePaid" DECIMAL(12,4),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PurchaseOrderLine_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."Supplier" (
    "id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "website" TEXT,
    "email" TEXT,
    "leadTime" INTEGER,
    "apiToken" TEXT,
    "apiKey" TEXT,
    "apiSecret" TEXT,
    "apiEndpoint" TEXT,
    "autoReorder" BOOLEAN NOT NULL DEFAULT false,
    "associatedItemTypes" "inventory"."ItemType"[] DEFAULT ARRAY[]::"inventory"."ItemType"[],
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Supplier_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."Sku" (
    "id" UUID NOT NULL,
    "productId" UUID NOT NULL,
    "code" TEXT NOT NULL,
    "channel" "inventory"."InventoryChannel" NOT NULL,
    "marketplace" "inventory"."Marketplace" NOT NULL DEFAULT 'AMAZON_FBA',
    "isDefault" BOOLEAN NOT NULL DEFAULT false,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "minStock" INTEGER NOT NULL DEFAULT 0,
    "currentStock" INTEGER NOT NULL DEFAULT 0,
    "dimensionsId" UUID,
    "requiresSecondaryPackage" BOOLEAN NOT NULL DEFAULT false,
    "finalStageType" "inventory"."AssemblyStageType" NOT NULL DEFAULT 'SECOND_STAGE',
    "locationId" UUID,
    "ean" TEXT,
    "asin" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Sku_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."AmazonProduct" (
    "id" UUID NOT NULL,
    "productItemId" UUID,
    "fulfillmentType" "inventory"."FulfillmentType" NOT NULL DEFAULT 'FBA',
    "listingStatus" "inventory"."ListingStatus" NOT NULL DEFAULT 'ACTIVE',
    "quantityTotal" INTEGER NOT NULL DEFAULT 0,
    "quantityInbound" INTEGER NOT NULL DEFAULT 0,
    "quantityTransfer" INTEGER NOT NULL DEFAULT 0,
    "quantityAvailable" INTEGER NOT NULL DEFAULT 0,
    "quantityReserved" INTEGER NOT NULL DEFAULT 0,
    "inboundShipment" BOOLEAN NOT NULL DEFAULT false,
    "price" DECIMAL(12,4),
    "salesVelocity" DECIMAL(12,4),
    "stockDays" INTEGER,
    "restockDate" TIMESTAMPTZ(6),
    "restockAction" "inventory"."RestockAction",
    "optimalLotSize" INTEGER,
    "dimensionsId" UUID,
    "weight" DECIMAL(12,3) NOT NULL DEFAULT 0,
    "orderStatus" "inventory"."AmazonOrderStatus" DEFAULT 'TO_ORDER',
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "skuId" UUID,

    CONSTRAINT "AmazonProduct_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."AmazonSalesData" (
    "id" UUID NOT NULL,
    "fbaProductId" UUID NOT NULL,
    "date" DATE NOT NULL,
    "unitsSold" INTEGER NOT NULL,
    "asin" TEXT NOT NULL,
    "sku" TEXT NOT NULL,
    "amazonOrderId" TEXT,
    "uniqueIdentifier" TEXT,

    CONSTRAINT "AmazonSalesData_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."AmazonIgnoredAsin" (
    "asin" TEXT NOT NULL,
    "note" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AmazonIgnoredAsin_pkey" PRIMARY KEY ("asin")
);

-- CreateTable
CREATE TABLE "inventory"."Shipment" (
    "id" UUID NOT NULL,
    "number" BIGSERIAL NOT NULL,
    "movementId" UUID,
    "productId" UUID,
    "orderedAt" TIMESTAMPTZ(6) NOT NULL,
    "shippedAt" TIMESTAMPTZ(6),
    "courier" TEXT,
    "labelUrl" TEXT,
    "isShipped" BOOLEAN NOT NULL DEFAULT false,
    "orderNumber" TEXT,
    "recipientCountry" TEXT,
    "recipientName" TEXT,
    "trackingNumber" TEXT,
    "trackingUrl" TEXT,
    "labelStatus" "inventory"."ShipmentLabelStatus" NOT NULL DEFAULT 'PENDING',
    "shipmentType" "inventory"."ShipmentType" NOT NULL DEFAULT 'STANDARD',
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "fullAddress" TEXT,
    "notes" TEXT,

    CONSTRAINT "Shipment_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."ShipmentLine" (
    "id" UUID NOT NULL,
    "shipmentId" UUID NOT NULL,
    "skuId" UUID NOT NULL,
    "quantity" INTEGER NOT NULL DEFAULT 1,
    "skuCodeSnapshot" TEXT,
    "lotId" UUID,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ShipmentLine_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."Settings" (
    "id" UUID NOT NULL,
    "name" "inventory"."SettingsName" NOT NULL,
    "value" JSONB NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Settings_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."_ItemToItemPart" (
    "A" UUID NOT NULL,
    "B" UUID NOT NULL,

    CONSTRAINT "_ItemToItemPart_AB_pkey" PRIMARY KEY ("A","B")
);

-- CreateTable
CREATE TABLE "inventory"."_ItemToProjectThreeMFFile" (
    "A" UUID NOT NULL,
    "B" UUID NOT NULL,

    CONSTRAINT "_ItemToProjectThreeMFFile_AB_pkey" PRIMARY KEY ("A","B")
);

-- CreateTable
CREATE TABLE "inventory"."_ItemToProductionJob" (
    "A" UUID NOT NULL,
    "B" UUID NOT NULL,

    CONSTRAINT "_ItemToProductionJob_AB_pkey" PRIMARY KEY ("A","B")
);

-- CreateTable
CREATE TABLE "inventory"."_ItemToPrintRun" (
    "A" UUID NOT NULL,
    "B" UUID NOT NULL,

    CONSTRAINT "_ItemToPrintRun_AB_pkey" PRIMARY KEY ("A","B")
);

-- CreateTable
CREATE TABLE "inventory"."_SpareParts" (
    "A" UUID NOT NULL,
    "B" UUID NOT NULL,

    CONSTRAINT "_SpareParts_AB_pkey" PRIMARY KEY ("A","B")
);

-- CreateTable
CREATE TABLE "print-farm"."_ProjectRelatedSku" (
    "A" UUID NOT NULL,
    "B" UUID NOT NULL,

    CONSTRAINT "_ProjectRelatedSku_AB_pkey" PRIMARY KEY ("A","B")
);

-- CreateTable
CREATE TABLE "print-farm"."_JobsToFiles" (
    "A" UUID NOT NULL,
    "B" UUID NOT NULL,

    CONSTRAINT "_JobsToFiles_AB_pkey" PRIMARY KEY ("A","B")
);

-- CreateTable
CREATE TABLE "print-farm"."_ProductionJobParts" (
    "A" UUID NOT NULL,
    "B" UUID NOT NULL,

    CONSTRAINT "_ProductionJobParts_AB_pkey" PRIMARY KEY ("A","B")
);

-- CreateTable
CREATE TABLE "print-farm"."_PrinterCompatibility" (
    "A" UUID NOT NULL,
    "B" INTEGER NOT NULL,

    CONSTRAINT "_PrinterCompatibility_AB_pkey" PRIMARY KEY ("A","B")
);

-- CreateTable
CREATE TABLE "print-farm"."_PrinterModelMacroCompatibility" (
    "A" INTEGER NOT NULL,
    "B" INTEGER NOT NULL,

    CONSTRAINT "_PrinterModelMacroCompatibility_AB_pkey" PRIMARY KEY ("A","B")
);

-- CreateTable
CREATE TABLE "print-farm"."_PrinterModelErrorCode" (
    "A" INTEGER NOT NULL,
    "B" INTEGER NOT NULL,

    CONSTRAINT "_PrinterModelErrorCode_AB_pkey" PRIMARY KEY ("A","B")
);

-- CreateTable
CREATE TABLE "inventory"."_OdetteToProductionJob" (
    "A" UUID NOT NULL,
    "B" UUID NOT NULL,

    CONSTRAINT "_OdetteToProductionJob_AB_pkey" PRIMARY KEY ("A","B")
);

-- CreateIndex
CREATE UNIQUE INDEX "Profile_userId_key" ON "Profile"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "User_email_key" ON "User"("email");

-- CreateIndex
CREATE UNIQUE INDEX "User_username_key" ON "User"("username");

-- CreateIndex
CREATE INDEX "User_isActive_idx" ON "User"("isActive");

-- CreateIndex
CREATE UNIQUE INDEX "Role_name_key" ON "Role"("name");

-- CreateIndex
CREATE INDEX "UserRole_userId_idx" ON "UserRole"("userId");

-- CreateIndex
CREATE INDEX "UserRole_roleId_idx" ON "UserRole"("roleId");

-- CreateIndex
CREATE UNIQUE INDEX "Permission_name_key" ON "Permission"("name");

-- CreateIndex
CREATE INDEX "Permission_resource_idx" ON "Permission"("resource");

-- CreateIndex
CREATE UNIQUE INDEX "Permission_resource_action_key" ON "Permission"("resource", "action");

-- CreateIndex
CREATE INDEX "RolePermission_roleId_idx" ON "RolePermission"("roleId");

-- CreateIndex
CREATE INDEX "RolePermission_permissionId_idx" ON "RolePermission"("permissionId");

-- CreateIndex
CREATE UNIQUE INDEX "Item_sku_key" ON "inventory"."Item"("sku");

-- CreateIndex
CREATE INDEX "Item_type_idx" ON "inventory"."Item"("type");

-- CreateIndex
CREATE INDEX "Item_categoryId_idx" ON "inventory"."Item"("categoryId");

-- CreateIndex
CREATE INDEX "Item_colorId_idx" ON "inventory"."Item"("colorId");

-- CreateIndex
CREATE INDEX "Item_brandId_idx" ON "inventory"."Item"("brandId");

-- CreateIndex
CREATE INDEX "Item_supplierId_idx" ON "inventory"."Item"("supplierId");

-- CreateIndex
CREATE INDEX "Item_locationId_idx" ON "inventory"."Item"("locationId");

-- CreateIndex
CREATE UNIQUE INDEX "Product_id_key" ON "inventory"."Product"("id");

-- CreateIndex
CREATE INDEX "Product_itemId_idx" ON "inventory"."Product"("itemId");

-- CreateIndex
CREATE UNIQUE INDEX "ProductPart_id_key" ON "inventory"."ProductPart"("id");

-- CreateIndex
CREATE INDEX "ProductPart_productId_idx" ON "inventory"."ProductPart"("productId");

-- CreateIndex
CREATE UNIQUE INDEX "Dimensions_id_key" ON "inventory"."Dimensions"("id");

-- CreateIndex
CREATE UNIQUE INDEX "AssemblyStage_id_key" ON "inventory"."AssemblyStage"("id");

-- CreateIndex
CREATE INDEX "AssemblyStage_productId_idx" ON "inventory"."AssemblyStage"("productId");

-- CreateIndex
CREATE UNIQUE INDEX "AssemblyStage_productId_name_key" ON "inventory"."AssemblyStage"("productId", "name");

-- CreateIndex
CREATE INDEX "Guide_productId_idx" ON "inventory"."Guide"("productId");

-- CreateIndex
CREATE INDEX "GuideToAssemblyStage_assemblyStageId_idx" ON "inventory"."GuideToAssemblyStage"("assemblyStageId");

-- CreateIndex
CREATE INDEX "Warning_productId_idx" ON "inventory"."Warning"("productId");

-- CreateIndex
CREATE INDEX "Warning_severity_idx" ON "inventory"."Warning"("severity");

-- CreateIndex
CREATE INDEX "WarningToAssemblyStage_assemblyStageId_idx" ON "inventory"."WarningToAssemblyStage"("assemblyStageId");

-- CreateIndex
CREATE INDEX "Category_associatedItemType_idx" ON "inventory"."Category"("associatedItemType");

-- CreateIndex
CREATE INDEX "Category_name_idx" ON "inventory"."Category"("name");

-- CreateIndex
CREATE UNIQUE INDEX "Category_name_associatedItemType_key" ON "inventory"."Category"("name", "associatedItemType");

-- CreateIndex
CREATE INDEX "PackagingType_associatedItemType_idx" ON "inventory"."PackagingType"("associatedItemType");

-- CreateIndex
CREATE INDEX "PackagingType_name_idx" ON "inventory"."PackagingType"("name");

-- CreateIndex
CREATE UNIQUE INDEX "PackagingType_name_associatedItemType_key" ON "inventory"."PackagingType"("name", "associatedItemType");

-- CreateIndex
CREATE INDEX "Color_associatedItemType_idx" ON "inventory"."Color"("associatedItemType");

-- CreateIndex
CREATE INDEX "Color_name_idx" ON "inventory"."Color"("name");

-- CreateIndex
CREATE UNIQUE INDEX "Color_name_associatedItemType_key" ON "inventory"."Color"("name", "associatedItemType");

-- CreateIndex
CREATE INDEX "Brand_associatedItemType_idx" ON "inventory"."Brand"("associatedItemType");

-- CreateIndex
CREATE INDEX "Brand_name_idx" ON "inventory"."Brand"("name");

-- CreateIndex
CREATE UNIQUE INDEX "Brand_name_associatedItemType_key" ON "inventory"."Brand"("name", "associatedItemType");

-- CreateIndex
CREATE INDEX "StandardWeight_associatedItemType_idx" ON "inventory"."StandardWeight"("associatedItemType");

-- CreateIndex
CREATE INDEX "CompatibleMachine_name_idx" ON "inventory"."CompatibleMachine"("name");

-- CreateIndex
CREATE INDEX "CompatibleMachine_associatedItemType_idx" ON "inventory"."CompatibleMachine"("associatedItemType");

-- CreateIndex
CREATE UNIQUE INDEX "CompatibleMachine_name_associatedItemType_key" ON "inventory"."CompatibleMachine"("name", "associatedItemType");

-- CreateIndex
CREATE INDEX "ProductToPackage_itemId_idx" ON "inventory"."ProductToPackage"("itemId");

-- CreateIndex
CREATE INDEX "ProductToTool_itemId_idx" ON "inventory"."ProductToTool"("itemId");

-- CreateIndex
CREATE INDEX "ProductToUtility_itemId_idx" ON "inventory"."ProductToUtility"("itemId");

-- CreateIndex
CREATE INDEX "ProductToUtility_assemblyStageId_idx" ON "inventory"."ProductToUtility"("assemblyStageId");

-- CreateIndex
CREATE INDEX "ProductToComponent_itemId_idx" ON "inventory"."ProductToComponent"("itemId");

-- CreateIndex
CREATE INDEX "Movement_productPartId_idx" ON "inventory"."Movement"("productPartId");

-- CreateIndex
CREATE INDEX "Movement_assemblyStageId_idx" ON "inventory"."Movement"("assemblyStageId");

-- CreateIndex
CREATE INDEX "Movement_productId_idx" ON "inventory"."Movement"("productId");

-- CreateIndex
CREATE INDEX "Movement_itemId_idx" ON "inventory"."Movement"("itemId");

-- CreateIndex
CREATE INDEX "Movement_channel_idx" ON "inventory"."Movement"("channel");

-- CreateIndex
CREATE INDEX "Movement_skuId_idx" ON "inventory"."Movement"("skuId");

-- CreateIndex
CREATE INDEX "Movement_odetteId_idx" ON "inventory"."Movement"("odetteId");

-- CreateIndex
CREATE INDEX "Movement_lotId_idx" ON "inventory"."Movement"("lotId");

-- CreateIndex
CREATE INDEX "Movement_date_idx" ON "inventory"."Movement"("date");

-- CreateIndex
CREATE UNIQUE INDEX "InventoryLot_number_key" ON "inventory"."InventoryLot"("number");

-- CreateIndex
CREATE UNIQUE INDEX "InventoryLot_code_key" ON "inventory"."InventoryLot"("code");

-- CreateIndex
CREATE INDEX "InventoryLot_originType_idx" ON "inventory"."InventoryLot"("originType");

-- CreateIndex
CREATE INDEX "InventoryLot_status_idx" ON "inventory"."InventoryLot"("status");

-- CreateIndex
CREATE INDEX "InventoryLot_itemId_idx" ON "inventory"."InventoryLot"("itemId");

-- CreateIndex
CREATE INDEX "InventoryLot_productId_idx" ON "inventory"."InventoryLot"("productId");

-- CreateIndex
CREATE INDEX "InventoryLot_purchaseOrderLineId_idx" ON "inventory"."InventoryLot"("purchaseOrderLineId");

-- CreateIndex
CREATE INDEX "InventoryLot_productItemOrderId_idx" ON "inventory"."InventoryLot"("productItemOrderId");

-- CreateIndex
CREATE INDEX "InventoryLot_assemblyOrderId_idx" ON "inventory"."InventoryLot"("assemblyOrderId");

-- CreateIndex
CREATE INDEX "InventoryLot_supplierId_idx" ON "inventory"."InventoryLot"("supplierId");

-- CreateIndex
CREATE INDEX "InventoryLot_productionLotId_idx" ON "inventory"."InventoryLot"("productionLotId");

-- CreateIndex
CREATE UNIQUE INDEX "WarehouseShelf_code_key" ON "inventory"."WarehouseShelf"("code");

-- CreateIndex
CREATE INDEX "WarehouseShelf_code_idx" ON "inventory"."WarehouseShelf"("code");

-- CreateIndex
CREATE INDEX "WarehouseShelf_name_idx" ON "inventory"."WarehouseShelf"("name");

-- CreateIndex
CREATE UNIQUE INDEX "WarehouseRow_code_key" ON "inventory"."WarehouseRow"("code");

-- CreateIndex
CREATE INDEX "WarehouseRow_shelfId_idx" ON "inventory"."WarehouseRow"("shelfId");

-- CreateIndex
CREATE INDEX "WarehouseRow_shelfId_orderInShelf_idx" ON "inventory"."WarehouseRow"("shelfId", "orderInShelf");

-- CreateIndex
CREATE INDEX "WarehouseRow_rowType_idx" ON "inventory"."WarehouseRow"("rowType");

-- CreateIndex
CREATE INDEX "WarehouseRow_itemType_idx" ON "inventory"."WarehouseRow"("itemType");

-- CreateIndex
CREATE INDEX "WarehouseRow_categoryId_idx" ON "inventory"."WarehouseRow"("categoryId");

-- CreateIndex
CREATE UNIQUE INDEX "WarehouseLocation_name_key" ON "inventory"."WarehouseLocation"("name");

-- CreateIndex
CREATE INDEX "WarehouseLocation_name_idx" ON "inventory"."WarehouseLocation"("name");

-- CreateIndex
CREATE INDEX "WarehouseLocation_rowId_positionInRow_idx" ON "inventory"."WarehouseLocation"("rowId", "positionInRow");

-- CreateIndex
CREATE INDEX "WarehouseLocation_kind_idx" ON "inventory"."WarehouseLocation"("kind");

-- CreateIndex
CREATE INDEX "WarehouseLocation_associatedItemType_idx" ON "inventory"."WarehouseLocation"("associatedItemType");

-- CreateIndex
CREATE INDEX "WarehouseItemAllocation_locationId_idx" ON "inventory"."WarehouseItemAllocation"("locationId");

-- CreateIndex
CREATE INDEX "WarehouseItemAllocation_itemId_idx" ON "inventory"."WarehouseItemAllocation"("itemId");

-- CreateIndex
CREATE UNIQUE INDEX "WarehouseItemAllocation_locationId_itemId_key" ON "inventory"."WarehouseItemAllocation"("locationId", "itemId");

-- CreateIndex
CREATE INDEX "WarehouseSkuAllocation_locationId_idx" ON "inventory"."WarehouseSkuAllocation"("locationId");

-- CreateIndex
CREATE INDEX "WarehouseSkuAllocation_skuId_idx" ON "inventory"."WarehouseSkuAllocation"("skuId");

-- CreateIndex
CREATE UNIQUE INDEX "WarehouseSkuAllocation_locationId_skuId_key" ON "inventory"."WarehouseSkuAllocation"("locationId", "skuId");

-- CreateIndex
CREATE INDEX "LotInspection_lotId_idx" ON "inventory"."LotInspection"("lotId");

-- CreateIndex
CREATE INDEX "LotInspection_inspectedBy_idx" ON "inventory"."LotInspection"("inspectedBy");

-- CreateIndex
CREATE INDEX "FinishedAllocation_productItemId_channel_idx" ON "inventory"."FinishedAllocation"("productItemId", "channel");

-- CreateIndex
CREATE INDEX "FinishedAllocation_skuId_idx" ON "inventory"."FinishedAllocation"("skuId");

-- CreateIndex
CREATE UNIQUE INDEX "FinishedAllocation_productItemId_assemblyStageId_channel_sk_key" ON "inventory"."FinishedAllocation"("productItemId", "assemblyStageId", "channel", "skuId");

-- CreateIndex
CREATE UNIQUE INDEX "PrinterMaintenanceLog_number_key" ON "print-farm"."PrinterMaintenanceLog"("number");

-- CreateIndex
CREATE UNIQUE INDEX "PrinterIssue_number_key" ON "print-farm"."PrinterIssue"("number");

-- CreateIndex
CREATE INDEX "PrinterIssue_printerId_status_idx" ON "print-farm"."PrinterIssue"("printerId", "status");

-- CreateIndex
CREATE INDEX "PrinterIssue_printerId_category_status_idx" ON "print-farm"."PrinterIssue"("printerId", "category", "status");

-- CreateIndex
CREATE INDEX "PrinterIssue_assignmentId_idx" ON "print-farm"."PrinterIssue"("assignmentId");

-- CreateIndex
CREATE INDEX "PrinterIssue_errorCodeId_idx" ON "print-farm"."PrinterIssue"("errorCodeId");

-- CreateIndex
CREATE INDEX "PrinterIssue_lastSeenAt_idx" ON "print-farm"."PrinterIssue"("lastSeenAt");

-- CreateIndex
CREATE UNIQUE INDEX "PrintFailureLog_number_key" ON "print-farm"."PrintFailureLog"("number");

-- CreateIndex
CREATE UNIQUE INDEX "FarmFeedback_number_key" ON "print-farm"."FarmFeedback"("number");

-- CreateIndex
CREATE UNIQUE INDEX "FilamentProfile_itemId_key" ON "print-farm"."FilamentProfile"("itemId");

-- CreateIndex
CREATE UNIQUE INDEX "FilamentProfile_bambuCode_key" ON "print-farm"."FilamentProfile"("bambuCode");

-- CreateIndex
CREATE UNIQUE INDEX "FilamentSpool_nfcTagId_key" ON "print-farm"."FilamentSpool"("nfcTagId");

-- CreateIndex
CREATE INDEX "FilamentSpool_inventoryLotId_idx" ON "print-farm"."FilamentSpool"("inventoryLotId");

-- CreateIndex
CREATE UNIQUE INDEX "ProjectThreeMFFile_previousVersionId_key" ON "print-farm"."ProjectThreeMFFile"("previousVersionId");

-- CreateIndex
CREATE INDEX "ProjectThreeMFFile_productId_idx" ON "print-farm"."ProjectThreeMFFile"("productId");

-- CreateIndex
CREATE INDEX "ProjectThreeMFFile_status_idx" ON "print-farm"."ProjectThreeMFFile"("status");

-- CreateIndex
CREATE INDEX "ProjectThreeMFFile_previousVersionId_idx" ON "print-farm"."ProjectThreeMFFile"("previousVersionId");

-- CreateIndex
CREATE INDEX "ProjectFileMaterial_fileId_idx" ON "print-farm"."ProjectFileMaterial"("fileId");

-- CreateIndex
CREATE INDEX "ProjectFileMaterial_materialId_idx" ON "print-farm"."ProjectFileMaterial"("materialId");

-- CreateIndex
CREATE UNIQUE INDEX "ProjectFileMaterial_fileId_materialId_key" ON "print-farm"."ProjectFileMaterial"("fileId", "materialId");

-- CreateIndex
CREATE INDEX "ProjectPart_productPartId_idx" ON "print-farm"."ProjectPart"("productPartId");

-- CreateIndex
CREATE INDEX "ProjectPart_productId_idx" ON "print-farm"."ProjectPart"("productId");

-- CreateIndex
CREATE INDEX "ProjectPart_fileId_idx" ON "print-farm"."ProjectPart"("fileId");

-- CreateIndex
CREATE UNIQUE INDEX "ProductionJob_number_key" ON "print-farm"."ProductionJob"("number");

-- CreateIndex
CREATE INDEX "ProductionJob_productOrderId_idx" ON "print-farm"."ProductionJob"("productOrderId");

-- CreateIndex
CREATE INDEX "ProductionJob_assemblyOrderId_idx" ON "print-farm"."ProductionJob"("assemblyOrderId");

-- CreateIndex
CREATE INDEX "ProductionJob_productId_idx" ON "print-farm"."ProductionJob"("productId");

-- CreateIndex
CREATE INDEX "ProductionJob_productPartId_idx" ON "print-farm"."ProductionJob"("productPartId");

-- CreateIndex
CREATE INDEX "ProductionJob_status_idx" ON "print-farm"."ProductionJob"("status");

-- CreateIndex
CREATE UNIQUE INDEX "PrintRun_number_key" ON "print-farm"."PrintRun"("number");

-- CreateIndex
CREATE INDEX "PrintRun_assignmentId_idx" ON "print-farm"."PrintRun"("assignmentId");

-- CreateIndex
CREATE INDEX "PrintRun_productionJobId_idx" ON "print-farm"."PrintRun"("productionJobId");

-- CreateIndex
CREATE INDEX "PrintRun_fileId_idx" ON "print-farm"."PrintRun"("fileId");

-- CreateIndex
CREATE INDEX "PrintRun_spoolId_idx" ON "print-farm"."PrintRun"("spoolId");

-- CreateIndex
CREATE INDEX "PrintRun_status_idx" ON "print-farm"."PrintRun"("status");

-- CreateIndex
CREATE INDEX "PrintRun_startedAt_idx" ON "print-farm"."PrintRun"("startedAt");

-- CreateIndex
CREATE UNIQUE INDEX "Printer_bedOccupiedAssignmentId_key" ON "print-farm"."Printer"("bedOccupiedAssignmentId");

-- CreateIndex
CREATE INDEX "Printer_operationalStatus_idx" ON "print-farm"."Printer"("operationalStatus");

-- CreateIndex
CREATE INDEX "Printer_manualOverrideStatus_idx" ON "print-farm"."Printer"("manualOverrideStatus");

-- CreateIndex
CREATE INDEX "Printer_bedOccupied_idx" ON "print-farm"."Printer"("bedOccupied");

-- CreateIndex
CREATE INDEX "Printer_locationId_idx" ON "print-farm"."Printer"("locationId");

-- CreateIndex
CREATE UNIQUE INDEX "PrinterModel_name_key" ON "print-farm"."PrinterModel"("name");

-- CreateIndex
CREATE UNIQUE INDEX "ErrorCode_code_key" ON "print-farm"."ErrorCode"("code");

-- CreateIndex
CREATE INDEX "PrinterLogs_printerId_idx" ON "print-farm"."PrinterLogs"("printerId");

-- CreateIndex
CREATE INDEX "PrinterLogs_occurredAt_idx" ON "print-farm"."PrinterLogs"("occurredAt");

-- CreateIndex
CREATE UNIQUE INDEX "Settings_settingsname_settingstype_key" ON "print-farm"."Settings"("settingsname", "settingstype");

-- CreateIndex
CREATE UNIQUE INDEX "PrinterAssignment_number_key" ON "print-farm"."PrinterAssignment"("number");

-- CreateIndex
CREATE INDEX "PrinterAssignment_productionJobId_idx" ON "print-farm"."PrinterAssignment"("productionJobId");

-- CreateIndex
CREATE INDEX "PrinterAssignment_printerId_idx" ON "print-farm"."PrinterAssignment"("printerId");

-- CreateIndex
CREATE INDEX "PrinterAssignment_status_idx" ON "print-farm"."PrinterAssignment"("status");

-- CreateIndex
CREATE INDEX "PrinterAssignment_queuePosition_idx" ON "print-farm"."PrinterAssignment"("queuePosition");

-- CreateIndex
CREATE UNIQUE INDEX "PrinterAssignment_productionJobId_printerId_key" ON "print-farm"."PrinterAssignment"("productionJobId", "printerId");

-- CreateIndex
CREATE INDEX "PrinterHarvest_assignmentId_idx" ON "print-farm"."PrinterHarvest"("assignmentId");

-- CreateIndex
CREATE INDEX "PrinterHarvest_printerId_idx" ON "print-farm"."PrinterHarvest"("printerId");

-- CreateIndex
CREATE INDEX "PrinterHarvest_odetteId_idx" ON "print-farm"."PrinterHarvest"("odetteId");

-- CreateIndex
CREATE INDEX "PrinterHarvest_harvestedByUserId_idx" ON "print-farm"."PrinterHarvest"("harvestedByUserId");

-- CreateIndex
CREATE INDEX "PrinterHarvest_harvestedAt_idx" ON "print-farm"."PrinterHarvest"("harvestedAt");

-- CreateIndex
CREATE INDEX "PrinterHarvest_productionLotId_idx" ON "print-farm"."PrinterHarvest"("productionLotId");

-- CreateIndex
CREATE INDEX "PrinterFilamentLoad_assignmentId_idx" ON "print-farm"."PrinterFilamentLoad"("assignmentId");

-- CreateIndex
CREATE INDEX "PrinterFilamentLoad_printerId_idx" ON "print-farm"."PrinterFilamentLoad"("printerId");

-- CreateIndex
CREATE INDEX "PrinterFilamentLoad_loadedByUserId_idx" ON "print-farm"."PrinterFilamentLoad"("loadedByUserId");

-- CreateIndex
CREATE INDEX "PrinterFilamentLoad_loadedAt_idx" ON "print-farm"."PrinterFilamentLoad"("loadedAt");

-- CreateIndex
CREATE UNIQUE INDEX "ProductOrder_number_key" ON "inventory"."ProductOrder"("number");

-- CreateIndex
CREATE INDEX "ProductOrder_skuId_idx" ON "inventory"."ProductOrder"("skuId");

-- CreateIndex
CREATE INDEX "ProductOrder_assemblyOrderId_idx" ON "inventory"."ProductOrder"("assemblyOrderId");

-- CreateIndex
CREATE INDEX "ProductOrder_producedByUserId_idx" ON "inventory"."ProductOrder"("producedByUserId");

-- CreateIndex
CREATE INDEX "ProductOrder_productionStatus_idx" ON "inventory"."ProductOrder"("productionStatus");

-- CreateIndex
CREATE INDEX "ProductOrder_priority_idx" ON "inventory"."ProductOrder"("priority");

-- CreateIndex
CREATE INDEX "ProductOrderItem_itemId_idx" ON "inventory"."ProductOrderItem"("itemId");

-- CreateIndex
CREATE INDEX "ProductOrderProductPart_productPartId_idx" ON "inventory"."ProductOrderProductPart"("productPartId");

-- CreateIndex
CREATE UNIQUE INDEX "AssemblyOrder_number_key" ON "inventory"."AssemblyOrder"("number");

-- CreateIndex
CREATE INDEX "AssemblyOrder_assembledByUserId_idx" ON "inventory"."AssemblyOrder"("assembledByUserId");

-- CreateIndex
CREATE INDEX "AssemblyOrder_skuId_idx" ON "inventory"."AssemblyOrder"("skuId");

-- CreateIndex
CREATE INDEX "AssemblyOperation_assemblyOrderId_idx" ON "inventory"."AssemblyOperation"("assemblyOrderId");

-- CreateIndex
CREATE INDEX "AssemblyOperation_operatorId_idx" ON "inventory"."AssemblyOperation"("operatorId");

-- CreateIndex
CREATE INDEX "AssemblyOperation_lotId_idx" ON "inventory"."AssemblyOperation"("lotId");

-- CreateIndex
CREATE INDEX "AssemblyOperation_assemblyStageId_idx" ON "inventory"."AssemblyOperation"("assemblyStageId");

-- CreateIndex
CREATE UNIQUE INDEX "ProductionLot_number_key" ON "inventory"."ProductionLot"("number");

-- CreateIndex
CREATE UNIQUE INDEX "ProductionLot_code_key" ON "inventory"."ProductionLot"("code");

-- CreateIndex
CREATE UNIQUE INDEX "Odette_code_key" ON "inventory"."Odette"("code");

-- CreateIndex
CREATE UNIQUE INDEX "Odette_barcode_key" ON "inventory"."Odette"("barcode");

-- CreateIndex
CREATE INDEX "Odette_status_idx" ON "inventory"."Odette"("status");

-- CreateIndex
CREATE INDEX "Odette_lockedStage_idx" ON "inventory"."Odette"("lockedStage");

-- CreateIndex
CREATE INDEX "Odette_locationId_idx" ON "inventory"."Odette"("locationId");

-- CreateIndex
CREATE INDEX "Odette_status_typeId_locationId_idx" ON "inventory"."Odette"("status", "typeId", "locationId");

-- CreateIndex
CREATE INDEX "Odette_reservedLotId_idx" ON "inventory"."Odette"("reservedLotId");

-- CreateIndex
CREATE INDEX "OdetteContent_odetteId_idx" ON "inventory"."OdetteContent"("odetteId");

-- CreateIndex
CREATE INDEX "OdetteContent_itemId_idx" ON "inventory"."OdetteContent"("itemId");

-- CreateIndex
CREATE INDEX "OdetteContent_PartId_idx" ON "inventory"."OdetteContent"("PartId");

-- CreateIndex
CREATE INDEX "OdetteContent_assemblyStageId_idx" ON "inventory"."OdetteContent"("assemblyStageId");

-- CreateIndex
CREATE INDEX "OdetteContent_inventoryLotId_idx" ON "inventory"."OdetteContent"("inventoryLotId");

-- CreateIndex
CREATE INDEX "OdetteContent_skuId_idx" ON "inventory"."OdetteContent"("skuId");

-- CreateIndex
CREATE INDEX "OdetteReservation_odetteId_idx" ON "inventory"."OdetteReservation"("odetteId");

-- CreateIndex
CREATE INDEX "OdetteReservation_odetteContentId_idx" ON "inventory"."OdetteReservation"("odetteContentId");

-- CreateIndex
CREATE INDEX "OdetteReservation_assemblyOrderId_idx" ON "inventory"."OdetteReservation"("assemblyOrderId");

-- CreateIndex
CREATE INDEX "OdetteReservation_channel_idx" ON "inventory"."OdetteReservation"("channel");

-- CreateIndex
CREATE INDEX "OdetteReservation_skuId_idx" ON "inventory"."OdetteReservation"("skuId");

-- CreateIndex
CREATE INDEX "OdetteMove_odetteId_idx" ON "inventory"."OdetteMove"("odetteId");

-- CreateIndex
CREATE INDEX "OdetteMove_fromLocationId_idx" ON "inventory"."OdetteMove"("fromLocationId");

-- CreateIndex
CREATE INDEX "OdetteMove_toLocationId_idx" ON "inventory"."OdetteMove"("toLocationId");

-- CreateIndex
CREATE INDEX "OdetteMove_movedByUser_idx" ON "inventory"."OdetteMove"("movedByUser");

-- CreateIndex
CREATE INDEX "OdetteCleaningLog_odetteId_idx" ON "inventory"."OdetteCleaningLog"("odetteId");

-- CreateIndex
CREATE INDEX "OdetteCleaningLog_byUserId_idx" ON "inventory"."OdetteCleaningLog"("byUserId");

-- CreateIndex
CREATE UNIQUE INDEX "OdetteType_name_key" ON "inventory"."OdetteType"("name");

-- CreateIndex
CREATE UNIQUE INDEX "OdetteType_code_key" ON "inventory"."OdetteType"("code");

-- CreateIndex
CREATE INDEX "OdetteType_purpose_idx" ON "inventory"."OdetteType"("purpose");

-- CreateIndex
CREATE INDEX "OdetteType_categoryId_idx" ON "inventory"."OdetteType"("categoryId");

-- CreateIndex
CREATE INDEX "OdetteLocationPreference_kind_idx" ON "inventory"."OdetteLocationPreference"("kind");

-- CreateIndex
CREATE UNIQUE INDEX "OdetteLocationPreference_locationId_kind_key" ON "inventory"."OdetteLocationPreference"("locationId", "kind");

-- CreateIndex
CREATE INDEX "OdetteAssemblyAssignment_assemblyOrderId_idx" ON "inventory"."OdetteAssemblyAssignment"("assemblyOrderId");

-- CreateIndex
CREATE INDEX "OdetteAssemblyAssignment_odetteId_idx" ON "inventory"."OdetteAssemblyAssignment"("odetteId");

-- CreateIndex
CREATE INDEX "OdetteAssemblyAssignment_stage_idx" ON "inventory"."OdetteAssemblyAssignment"("stage");

-- CreateIndex
CREATE INDEX "OdetteAssemblyAssignment_assemblyOrderId_stage_idx" ON "inventory"."OdetteAssemblyAssignment"("assemblyOrderId", "stage");

-- CreateIndex
CREATE UNIQUE INDEX "OdetteAssemblyAssignment_odetteId_assemblyOrderId_stage_rol_key" ON "inventory"."OdetteAssemblyAssignment"("odetteId", "assemblyOrderId", "stage", "role");

-- CreateIndex
CREATE UNIQUE INDEX "PurchaseOrder_number_key" ON "inventory"."PurchaseOrder"("number");

-- CreateIndex
CREATE INDEX "PurchaseOrder_supplierId_idx" ON "inventory"."PurchaseOrder"("supplierId");

-- CreateIndex
CREATE INDEX "PurchaseOrder_status_idx" ON "inventory"."PurchaseOrder"("status");

-- CreateIndex
CREATE INDEX "PurchaseOrder_orderedAt_idx" ON "inventory"."PurchaseOrder"("orderedAt");

-- CreateIndex
CREATE UNIQUE INDEX "PurchaseOrderLine_number_key" ON "inventory"."PurchaseOrderLine"("number");

-- CreateIndex
CREATE INDEX "PurchaseOrderLine_orderId_idx" ON "inventory"."PurchaseOrderLine"("orderId");

-- CreateIndex
CREATE INDEX "PurchaseOrderLine_itemId_idx" ON "inventory"."PurchaseOrderLine"("itemId");

-- CreateIndex
CREATE UNIQUE INDEX "Supplier_name_key" ON "inventory"."Supplier"("name");

-- CreateIndex
CREATE UNIQUE INDEX "Sku_code_key" ON "inventory"."Sku"("code");

-- CreateIndex
CREATE INDEX "Sku_productId_channel_marketplace_idx" ON "inventory"."Sku"("productId", "channel", "marketplace");

-- CreateIndex
CREATE INDEX "Sku_locationId_idx" ON "inventory"."Sku"("locationId");

-- CreateIndex
CREATE UNIQUE INDEX "AmazonProduct_productItemId_key" ON "inventory"."AmazonProduct"("productItemId");

-- CreateIndex
CREATE UNIQUE INDEX "AmazonProduct_skuId_key" ON "inventory"."AmazonProduct"("skuId");

-- CreateIndex
CREATE INDEX "AmazonProduct_productItemId_idx" ON "inventory"."AmazonProduct"("productItemId");

-- CreateIndex
CREATE INDEX "AmazonProduct_skuId_idx" ON "inventory"."AmazonProduct"("skuId");

-- CreateIndex
CREATE UNIQUE INDEX "AmazonSalesData_uniqueIdentifier_key" ON "inventory"."AmazonSalesData"("uniqueIdentifier");

-- CreateIndex
CREATE INDEX "AmazonSalesData_fbaProductId_idx" ON "inventory"."AmazonSalesData"("fbaProductId");

-- CreateIndex
CREATE INDEX "AmazonSalesData_amazonOrderId_idx" ON "inventory"."AmazonSalesData"("amazonOrderId");

-- CreateIndex
CREATE INDEX "AmazonIgnoredAsin_createdAt_idx" ON "inventory"."AmazonIgnoredAsin"("createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "Shipment_number_key" ON "inventory"."Shipment"("number");

-- CreateIndex
CREATE INDEX "Shipment_productId_idx" ON "inventory"."Shipment"("productId");

-- CreateIndex
CREATE INDEX "Shipment_movementId_idx" ON "inventory"."Shipment"("movementId");

-- CreateIndex
CREATE INDEX "ShipmentLine_shipmentId_idx" ON "inventory"."ShipmentLine"("shipmentId");

-- CreateIndex
CREATE INDEX "ShipmentLine_skuId_idx" ON "inventory"."ShipmentLine"("skuId");

-- CreateIndex
CREATE INDEX "ShipmentLine_lotId_idx" ON "inventory"."ShipmentLine"("lotId");

-- CreateIndex
CREATE UNIQUE INDEX "Settings_name_key" ON "inventory"."Settings"("name");

-- CreateIndex
CREATE INDEX "_ItemToItemPart_B_index" ON "inventory"."_ItemToItemPart"("B");

-- CreateIndex
CREATE INDEX "_ItemToProjectThreeMFFile_B_index" ON "inventory"."_ItemToProjectThreeMFFile"("B");

-- CreateIndex
CREATE INDEX "_ItemToProductionJob_B_index" ON "inventory"."_ItemToProductionJob"("B");

-- CreateIndex
CREATE INDEX "_ItemToPrintRun_B_index" ON "inventory"."_ItemToPrintRun"("B");

-- CreateIndex
CREATE INDEX "_SpareParts_B_index" ON "inventory"."_SpareParts"("B");

-- CreateIndex
CREATE INDEX "_ProjectRelatedSku_B_index" ON "print-farm"."_ProjectRelatedSku"("B");

-- CreateIndex
CREATE INDEX "_JobsToFiles_B_index" ON "print-farm"."_JobsToFiles"("B");

-- CreateIndex
CREATE INDEX "_ProductionJobParts_B_index" ON "print-farm"."_ProductionJobParts"("B");

-- CreateIndex
CREATE INDEX "_PrinterCompatibility_B_index" ON "print-farm"."_PrinterCompatibility"("B");

-- CreateIndex
CREATE INDEX "_PrinterModelMacroCompatibility_B_index" ON "print-farm"."_PrinterModelMacroCompatibility"("B");

-- CreateIndex
CREATE INDEX "_PrinterModelErrorCode_B_index" ON "print-farm"."_PrinterModelErrorCode"("B");

-- CreateIndex
CREATE INDEX "_OdetteToProductionJob_B_index" ON "inventory"."_OdetteToProductionJob"("B");

-- AddForeignKey
ALTER TABLE "Profile" ADD CONSTRAINT "Profile_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "UserRole" ADD CONSTRAINT "UserRole_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "UserRole" ADD CONSTRAINT "UserRole_roleId_fkey" FOREIGN KEY ("roleId") REFERENCES "Role"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RolePermission" ADD CONSTRAINT "RolePermission_roleId_fkey" FOREIGN KEY ("roleId") REFERENCES "Role"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RolePermission" ADD CONSTRAINT "RolePermission_permissionId_fkey" FOREIGN KEY ("permissionId") REFERENCES "Permission"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Post" ADD CONSTRAINT "Post_authorId_fkey" FOREIGN KEY ("authorId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."Item" ADD CONSTRAINT "Item_brandId_fkey" FOREIGN KEY ("brandId") REFERENCES "inventory"."Brand"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."Item" ADD CONSTRAINT "Item_categoryId_fkey" FOREIGN KEY ("categoryId") REFERENCES "inventory"."Category"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."Item" ADD CONSTRAINT "Item_colorId_fkey" FOREIGN KEY ("colorId") REFERENCES "inventory"."Color"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."Item" ADD CONSTRAINT "Item_locationId_fkey" FOREIGN KEY ("locationId") REFERENCES "inventory"."WarehouseLocation"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."Item" ADD CONSTRAINT "Item_packagingTypeId_fkey" FOREIGN KEY ("packagingTypeId") REFERENCES "inventory"."PackagingType"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."Item" ADD CONSTRAINT "Item_standardWeightId_fkey" FOREIGN KEY ("standardWeightId") REFERENCES "inventory"."StandardWeight"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."Item" ADD CONSTRAINT "Item_supplierId_fkey" FOREIGN KEY ("supplierId") REFERENCES "inventory"."Supplier"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."Item" ADD CONSTRAINT "Item_dimensionsId_fkey" FOREIGN KEY ("dimensionsId") REFERENCES "inventory"."Dimensions"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."Product" ADD CONSTRAINT "Product_itemId_fkey" FOREIGN KEY ("itemId") REFERENCES "inventory"."Item"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."Product" ADD CONSTRAINT "Product_dimensionsId_fkey" FOREIGN KEY ("dimensionsId") REFERENCES "inventory"."Dimensions"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."ProductPart" ADD CONSTRAINT "ProductPart_dimensionsId_fkey" FOREIGN KEY ("dimensionsId") REFERENCES "inventory"."Dimensions"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."ProductPart" ADD CONSTRAINT "ProductPart_productId_fkey" FOREIGN KEY ("productId") REFERENCES "inventory"."Product"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."AssemblyStage" ADD CONSTRAINT "AssemblyStage_productId_fkey" FOREIGN KEY ("productId") REFERENCES "inventory"."Product"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."Guide" ADD CONSTRAINT "Guide_productId_fkey" FOREIGN KEY ("productId") REFERENCES "inventory"."Product"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."GuideToAssemblyStage" ADD CONSTRAINT "GuideToAssemblyStage_guideId_fkey" FOREIGN KEY ("guideId") REFERENCES "inventory"."Guide"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."GuideToAssemblyStage" ADD CONSTRAINT "GuideToAssemblyStage_assemblyStageId_fkey" FOREIGN KEY ("assemblyStageId") REFERENCES "inventory"."AssemblyStage"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."Warning" ADD CONSTRAINT "Warning_productId_fkey" FOREIGN KEY ("productId") REFERENCES "inventory"."Product"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."WarningToAssemblyStage" ADD CONSTRAINT "WarningToAssemblyStage_warningId_fkey" FOREIGN KEY ("warningId") REFERENCES "inventory"."Warning"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."WarningToAssemblyStage" ADD CONSTRAINT "WarningToAssemblyStage_assemblyStageId_fkey" FOREIGN KEY ("assemblyStageId") REFERENCES "inventory"."AssemblyStage"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."ProductToPackage" ADD CONSTRAINT "ProductToPackage_itemId_fkey" FOREIGN KEY ("itemId") REFERENCES "inventory"."Item"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."ProductToPackage" ADD CONSTRAINT "ProductToPackage_productId_fkey" FOREIGN KEY ("productId") REFERENCES "inventory"."Product"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."ProductToTool" ADD CONSTRAINT "ProductToTool_itemId_fkey" FOREIGN KEY ("itemId") REFERENCES "inventory"."Item"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."ProductToTool" ADD CONSTRAINT "ProductToTool_productId_fkey" FOREIGN KEY ("productId") REFERENCES "inventory"."Product"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."ProductToUtility" ADD CONSTRAINT "ProductToUtility_itemId_fkey" FOREIGN KEY ("itemId") REFERENCES "inventory"."Item"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."ProductToUtility" ADD CONSTRAINT "ProductToUtility_productId_fkey" FOREIGN KEY ("productId") REFERENCES "inventory"."Product"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."ProductToUtility" ADD CONSTRAINT "ProductToUtility_assemblyStageId_fkey" FOREIGN KEY ("assemblyStageId") REFERENCES "inventory"."AssemblyStage"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."ProductToComponent" ADD CONSTRAINT "ProductToComponent_itemId_fkey" FOREIGN KEY ("itemId") REFERENCES "inventory"."Item"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."ProductToComponent" ADD CONSTRAINT "ProductToComponent_productId_fkey" FOREIGN KEY ("productId") REFERENCES "inventory"."Product"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."Movement" ADD CONSTRAINT "Movement_skuId_fkey" FOREIGN KEY ("skuId") REFERENCES "inventory"."Sku"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."Movement" ADD CONSTRAINT "Movement_odetteId_fkey" FOREIGN KEY ("odetteId") REFERENCES "inventory"."Odette"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."Movement" ADD CONSTRAINT "Movement_lotId_fkey" FOREIGN KEY ("lotId") REFERENCES "inventory"."InventoryLot"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."Movement" ADD CONSTRAINT "Movement_assemblyStageId_fkey" FOREIGN KEY ("assemblyStageId") REFERENCES "inventory"."AssemblyStage"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."Movement" ADD CONSTRAINT "Movement_itemId_fkey" FOREIGN KEY ("itemId") REFERENCES "inventory"."Item"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."Movement" ADD CONSTRAINT "Movement_productPartId_fkey" FOREIGN KEY ("productPartId") REFERENCES "inventory"."ProductPart"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."Movement" ADD CONSTRAINT "Movement_productId_fkey" FOREIGN KEY ("productId") REFERENCES "inventory"."Product"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."InventoryLot" ADD CONSTRAINT "InventoryLot_itemId_fkey" FOREIGN KEY ("itemId") REFERENCES "inventory"."Item"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."InventoryLot" ADD CONSTRAINT "InventoryLot_productId_fkey" FOREIGN KEY ("productId") REFERENCES "inventory"."Product"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."InventoryLot" ADD CONSTRAINT "InventoryLot_purchaseOrderLineId_fkey" FOREIGN KEY ("purchaseOrderLineId") REFERENCES "inventory"."PurchaseOrderLine"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."InventoryLot" ADD CONSTRAINT "InventoryLot_supplierId_fkey" FOREIGN KEY ("supplierId") REFERENCES "inventory"."Supplier"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."InventoryLot" ADD CONSTRAINT "InventoryLot_productItemOrderId_fkey" FOREIGN KEY ("productItemOrderId") REFERENCES "inventory"."ProductOrder"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."InventoryLot" ADD CONSTRAINT "InventoryLot_assemblyOrderId_fkey" FOREIGN KEY ("assemblyOrderId") REFERENCES "inventory"."AssemblyOrder"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."InventoryLot" ADD CONSTRAINT "InventoryLot_productionLotId_fkey" FOREIGN KEY ("productionLotId") REFERENCES "inventory"."ProductionLot"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."WarehouseRow" ADD CONSTRAINT "WarehouseRow_shelfId_fkey" FOREIGN KEY ("shelfId") REFERENCES "inventory"."WarehouseShelf"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."WarehouseRow" ADD CONSTRAINT "WarehouseRow_categoryId_fkey" FOREIGN KEY ("categoryId") REFERENCES "inventory"."Category"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."WarehouseLocation" ADD CONSTRAINT "WarehouseLocation_rowId_fkey" FOREIGN KEY ("rowId") REFERENCES "inventory"."WarehouseRow"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."WarehouseItemAllocation" ADD CONSTRAINT "WarehouseItemAllocation_locationId_fkey" FOREIGN KEY ("locationId") REFERENCES "inventory"."WarehouseLocation"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."WarehouseItemAllocation" ADD CONSTRAINT "WarehouseItemAllocation_itemId_fkey" FOREIGN KEY ("itemId") REFERENCES "inventory"."Item"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."WarehouseSkuAllocation" ADD CONSTRAINT "WarehouseSkuAllocation_locationId_fkey" FOREIGN KEY ("locationId") REFERENCES "inventory"."WarehouseLocation"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."WarehouseSkuAllocation" ADD CONSTRAINT "WarehouseSkuAllocation_skuId_fkey" FOREIGN KEY ("skuId") REFERENCES "inventory"."Sku"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."LotInspection" ADD CONSTRAINT "LotInspection_lotId_fkey" FOREIGN KEY ("lotId") REFERENCES "inventory"."InventoryLot"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."LotInspection" ADD CONSTRAINT "LotInspection_inspectedBy_fkey" FOREIGN KEY ("inspectedBy") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."FinishedAllocation" ADD CONSTRAINT "FinishedAllocation_skuId_fkey" FOREIGN KEY ("skuId") REFERENCES "inventory"."Sku"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."FinishedAllocation" ADD CONSTRAINT "FinishedAllocation_productItemId_fkey" FOREIGN KEY ("productItemId") REFERENCES "inventory"."Product"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."FinishedAllocation" ADD CONSTRAINT "FinishedAllocation_assemblyStageId_fkey" FOREIGN KEY ("assemblyStageId") REFERENCES "inventory"."AssemblyStage"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."PrinterMaintenanceLog" ADD CONSTRAINT "PrinterMaintenanceLog_printerId_fkey" FOREIGN KEY ("printerId") REFERENCES "print-farm"."Printer"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."PrinterIssue" ADD CONSTRAINT "PrinterIssue_printerId_fkey" FOREIGN KEY ("printerId") REFERENCES "print-farm"."Printer"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."PrinterIssue" ADD CONSTRAINT "PrinterIssue_assignmentId_fkey" FOREIGN KEY ("assignmentId") REFERENCES "print-farm"."PrinterAssignment"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."PrinterIssue" ADD CONSTRAINT "PrinterIssue_errorCodeId_fkey" FOREIGN KEY ("errorCodeId") REFERENCES "print-farm"."ErrorCode"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."PrintFailureLog" ADD CONSTRAINT "PrintFailureLog_productionJobId_fkey" FOREIGN KEY ("productionJobId") REFERENCES "print-farm"."ProductionJob"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."PrintFailureLog" ADD CONSTRAINT "PrintFailureLog_printerId_fkey" FOREIGN KEY ("printerId") REFERENCES "print-farm"."Printer"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."PrintFailureLog" ADD CONSTRAINT "PrintFailureLog_printRunId_fkey" FOREIGN KEY ("printRunId") REFERENCES "print-farm"."PrintRun"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."FarmFeedback" ADD CONSTRAINT "FarmFeedback_printerId_fkey" FOREIGN KEY ("printerId") REFERENCES "print-farm"."Printer"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."FarmFeedback" ADD CONSTRAINT "FarmFeedback_fileId_fkey" FOREIGN KEY ("fileId") REFERENCES "print-farm"."ProjectThreeMFFile"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."FilamentProfile" ADD CONSTRAINT "FilamentProfile_itemId_fkey" FOREIGN KEY ("itemId") REFERENCES "inventory"."Item"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."FilamentSpool" ADD CONSTRAINT "FilamentSpool_itemId_fkey" FOREIGN KEY ("itemId") REFERENCES "inventory"."Item"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."FilamentSpool" ADD CONSTRAINT "FilamentSpool_inventoryLotId_fkey" FOREIGN KEY ("inventoryLotId") REFERENCES "inventory"."InventoryLot"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."FilamentSpool" ADD CONSTRAINT "FilamentSpool_mountedOnId_fkey" FOREIGN KEY ("mountedOnId") REFERENCES "print-farm"."Printer"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."ProjectThreeMFFile" ADD CONSTRAINT "ProjectThreeMFFile_previousVersionId_fkey" FOREIGN KEY ("previousVersionId") REFERENCES "print-farm"."ProjectThreeMFFile"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."ProjectThreeMFFile" ADD CONSTRAINT "ProjectThreeMFFile_productId_fkey" FOREIGN KEY ("productId") REFERENCES "inventory"."Product"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."ProjectFileMaterial" ADD CONSTRAINT "ProjectFileMaterial_fileId_fkey" FOREIGN KEY ("fileId") REFERENCES "print-farm"."ProjectThreeMFFile"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."ProjectFileMaterial" ADD CONSTRAINT "ProjectFileMaterial_materialId_fkey" FOREIGN KEY ("materialId") REFERENCES "inventory"."Item"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."ProjectPart" ADD CONSTRAINT "ProjectPart_productPartId_fkey" FOREIGN KEY ("productPartId") REFERENCES "inventory"."ProductPart"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."ProjectPart" ADD CONSTRAINT "ProjectPart_productId_fkey" FOREIGN KEY ("productId") REFERENCES "inventory"."Product"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."ProjectPart" ADD CONSTRAINT "ProjectPart_fileId_fkey" FOREIGN KEY ("fileId") REFERENCES "print-farm"."ProjectThreeMFFile"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."ProductionJob" ADD CONSTRAINT "ProductionJob_productId_fkey" FOREIGN KEY ("productId") REFERENCES "inventory"."Product"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."ProductionJob" ADD CONSTRAINT "ProductionJob_productPartId_fkey" FOREIGN KEY ("productPartId") REFERENCES "inventory"."ProductPart"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."ProductionJob" ADD CONSTRAINT "ProductionJob_productOrderId_fkey" FOREIGN KEY ("productOrderId") REFERENCES "inventory"."ProductOrder"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."ProductionJob" ADD CONSTRAINT "ProductionJob_productionLotId_fkey" FOREIGN KEY ("productionLotId") REFERENCES "inventory"."ProductionLot"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."PrintRun" ADD CONSTRAINT "PrintRun_assignmentId_fkey" FOREIGN KEY ("assignmentId") REFERENCES "print-farm"."PrinterAssignment"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."PrintRun" ADD CONSTRAINT "PrintRun_productionJobId_fkey" FOREIGN KEY ("productionJobId") REFERENCES "print-farm"."ProductionJob"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."PrintRun" ADD CONSTRAINT "PrintRun_fileId_fkey" FOREIGN KEY ("fileId") REFERENCES "print-farm"."ProjectThreeMFFile"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."PrintRun" ADD CONSTRAINT "PrintRun_spoolId_fkey" FOREIGN KEY ("spoolId") REFERENCES "print-farm"."FilamentSpool"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."Printer" ADD CONSTRAINT "Printer_modelId_fkey" FOREIGN KEY ("modelId") REFERENCES "print-farm"."PrinterModel"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."Printer" ADD CONSTRAINT "Printer_bedOccupiedAssignmentId_fkey" FOREIGN KEY ("bedOccupiedAssignmentId") REFERENCES "print-farm"."PrinterAssignment"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."Printer" ADD CONSTRAINT "Printer_locationId_fkey" FOREIGN KEY ("locationId") REFERENCES "inventory"."WarehouseLocation"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."Printer" ADD CONSTRAINT "Printer_currentSpoolId_fkey" FOREIGN KEY ("currentSpoolId") REFERENCES "print-farm"."FilamentSpool"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."PrinterLogs" ADD CONSTRAINT "PrinterLogs_errorCodeId_fkey" FOREIGN KEY ("errorCodeId") REFERENCES "print-farm"."ErrorCode"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."PrinterLogs" ADD CONSTRAINT "PrinterLogs_printerId_fkey" FOREIGN KEY ("printerId") REFERENCES "print-farm"."Printer"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."PrinterAssignment" ADD CONSTRAINT "PrinterAssignment_productionJobId_fkey" FOREIGN KEY ("productionJobId") REFERENCES "print-farm"."ProductionJob"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."PrinterAssignment" ADD CONSTRAINT "PrinterAssignment_printerId_fkey" FOREIGN KEY ("printerId") REFERENCES "print-farm"."Printer"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."PrinterHarvest" ADD CONSTRAINT "PrinterHarvest_assignmentId_fkey" FOREIGN KEY ("assignmentId") REFERENCES "print-farm"."PrinterAssignment"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."PrinterHarvest" ADD CONSTRAINT "PrinterHarvest_printerId_fkey" FOREIGN KEY ("printerId") REFERENCES "print-farm"."Printer"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."PrinterHarvest" ADD CONSTRAINT "PrinterHarvest_odetteId_fkey" FOREIGN KEY ("odetteId") REFERENCES "inventory"."Odette"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."PrinterHarvest" ADD CONSTRAINT "PrinterHarvest_harvestedByUserId_fkey" FOREIGN KEY ("harvestedByUserId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."PrinterHarvest" ADD CONSTRAINT "PrinterHarvest_productionLotId_fkey" FOREIGN KEY ("productionLotId") REFERENCES "inventory"."ProductionLot"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."PrinterFilamentLoad" ADD CONSTRAINT "PrinterFilamentLoad_assignmentId_fkey" FOREIGN KEY ("assignmentId") REFERENCES "print-farm"."PrinterAssignment"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."PrinterFilamentLoad" ADD CONSTRAINT "PrinterFilamentLoad_printerId_fkey" FOREIGN KEY ("printerId") REFERENCES "print-farm"."Printer"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."PrinterFilamentLoad" ADD CONSTRAINT "PrinterFilamentLoad_loadedByUserId_fkey" FOREIGN KEY ("loadedByUserId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."PrinterFilamentLoad" ADD CONSTRAINT "PrinterFilamentLoad_spoolId_fkey" FOREIGN KEY ("spoolId") REFERENCES "print-farm"."FilamentSpool"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."ProductOrder" ADD CONSTRAINT "ProductOrder_productId_fkey" FOREIGN KEY ("productId") REFERENCES "inventory"."Product"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."ProductOrder" ADD CONSTRAINT "ProductOrder_skuId_fkey" FOREIGN KEY ("skuId") REFERENCES "inventory"."Sku"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."ProductOrder" ADD CONSTRAINT "ProductOrder_producedByUserId_fkey" FOREIGN KEY ("producedByUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."ProductOrder" ADD CONSTRAINT "ProductOrder_assemblyOrderId_fkey" FOREIGN KEY ("assemblyOrderId") REFERENCES "inventory"."AssemblyOrder"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."ProductOrderItem" ADD CONSTRAINT "ProductOrderItem_productOrderId_fkey" FOREIGN KEY ("productOrderId") REFERENCES "inventory"."ProductOrder"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."ProductOrderItem" ADD CONSTRAINT "ProductOrderItem_itemId_fkey" FOREIGN KEY ("itemId") REFERENCES "inventory"."Item"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."ProductOrderProductPart" ADD CONSTRAINT "ProductOrderProductPart_productOrderId_fkey" FOREIGN KEY ("productOrderId") REFERENCES "inventory"."ProductOrder"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."ProductOrderProductPart" ADD CONSTRAINT "ProductOrderProductPart_productPartId_fkey" FOREIGN KEY ("productPartId") REFERENCES "inventory"."ProductPart"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."AssemblyOrder" ADD CONSTRAINT "AssemblyOrder_productId_fkey" FOREIGN KEY ("productId") REFERENCES "inventory"."Product"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."AssemblyOrder" ADD CONSTRAINT "AssemblyOrder_skuId_fkey" FOREIGN KEY ("skuId") REFERENCES "inventory"."Sku"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."AssemblyOrder" ADD CONSTRAINT "AssemblyOrder_assembledByUserId_fkey" FOREIGN KEY ("assembledByUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."AssemblyOperation" ADD CONSTRAINT "AssemblyOperation_assemblyOrderId_fkey" FOREIGN KEY ("assemblyOrderId") REFERENCES "inventory"."AssemblyOrder"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."AssemblyOperation" ADD CONSTRAINT "AssemblyOperation_assemblyStageId_fkey" FOREIGN KEY ("assemblyStageId") REFERENCES "inventory"."AssemblyStage"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."AssemblyOperation" ADD CONSTRAINT "AssemblyOperation_operatorId_fkey" FOREIGN KEY ("operatorId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."AssemblyOperation" ADD CONSTRAINT "AssemblyOperation_lotId_fkey" FOREIGN KEY ("lotId") REFERENCES "inventory"."InventoryLot"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."Odette" ADD CONSTRAINT "Odette_typeId_fkey" FOREIGN KEY ("typeId") REFERENCES "inventory"."OdetteType"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."Odette" ADD CONSTRAINT "Odette_locationId_fkey" FOREIGN KEY ("locationId") REFERENCES "inventory"."WarehouseLocation"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."Odette" ADD CONSTRAINT "Odette_reservedLotId_fkey" FOREIGN KEY ("reservedLotId") REFERENCES "inventory"."ProductionLot"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."OdetteContent" ADD CONSTRAINT "OdetteContent_odetteId_fkey" FOREIGN KEY ("odetteId") REFERENCES "inventory"."Odette"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."OdetteContent" ADD CONSTRAINT "OdetteContent_itemId_fkey" FOREIGN KEY ("itemId") REFERENCES "inventory"."Item"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."OdetteContent" ADD CONSTRAINT "OdetteContent_PartId_fkey" FOREIGN KEY ("PartId") REFERENCES "inventory"."ProductPart"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."OdetteContent" ADD CONSTRAINT "OdetteContent_assemblyStageId_fkey" FOREIGN KEY ("assemblyStageId") REFERENCES "inventory"."AssemblyStage"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."OdetteContent" ADD CONSTRAINT "OdetteContent_skuId_fkey" FOREIGN KEY ("skuId") REFERENCES "inventory"."Sku"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."OdetteContent" ADD CONSTRAINT "OdetteContent_lotId_fkey" FOREIGN KEY ("lotId") REFERENCES "inventory"."ProductionLot"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."OdetteContent" ADD CONSTRAINT "OdetteContent_inventoryLotId_fkey" FOREIGN KEY ("inventoryLotId") REFERENCES "inventory"."InventoryLot"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."OdetteReservation" ADD CONSTRAINT "OdetteReservation_odetteId_fkey" FOREIGN KEY ("odetteId") REFERENCES "inventory"."Odette"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."OdetteReservation" ADD CONSTRAINT "OdetteReservation_odetteContentId_fkey" FOREIGN KEY ("odetteContentId") REFERENCES "inventory"."OdetteContent"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."OdetteReservation" ADD CONSTRAINT "OdetteReservation_assemblyOrderId_fkey" FOREIGN KEY ("assemblyOrderId") REFERENCES "inventory"."AssemblyOrder"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."OdetteReservation" ADD CONSTRAINT "OdetteReservation_skuId_fkey" FOREIGN KEY ("skuId") REFERENCES "inventory"."Sku"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."OdetteMove" ADD CONSTRAINT "OdetteMove_odetteId_fkey" FOREIGN KEY ("odetteId") REFERENCES "inventory"."Odette"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."OdetteMove" ADD CONSTRAINT "OdetteMove_fromLocationId_fkey" FOREIGN KEY ("fromLocationId") REFERENCES "inventory"."WarehouseLocation"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."OdetteMove" ADD CONSTRAINT "OdetteMove_toLocationId_fkey" FOREIGN KEY ("toLocationId") REFERENCES "inventory"."WarehouseLocation"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."OdetteMove" ADD CONSTRAINT "OdetteMove_movedByUser_fkey" FOREIGN KEY ("movedByUser") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."OdetteCleaningLog" ADD CONSTRAINT "OdetteCleaningLog_odetteId_fkey" FOREIGN KEY ("odetteId") REFERENCES "inventory"."Odette"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."OdetteCleaningLog" ADD CONSTRAINT "OdetteCleaningLog_byUserId_fkey" FOREIGN KEY ("byUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."OdetteType" ADD CONSTRAINT "OdetteType_categoryId_fkey" FOREIGN KEY ("categoryId") REFERENCES "inventory"."Category"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."OdetteType" ADD CONSTRAINT "OdetteType_dimensionsId_fkey" FOREIGN KEY ("dimensionsId") REFERENCES "inventory"."Dimensions"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."OdetteLocationPreference" ADD CONSTRAINT "OdetteLocationPreference_locationId_fkey" FOREIGN KEY ("locationId") REFERENCES "inventory"."WarehouseLocation"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."OdetteAssemblyAssignment" ADD CONSTRAINT "OdetteAssemblyAssignment_odetteId_fkey" FOREIGN KEY ("odetteId") REFERENCES "inventory"."Odette"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."OdetteAssemblyAssignment" ADD CONSTRAINT "OdetteAssemblyAssignment_assemblyOrderId_fkey" FOREIGN KEY ("assemblyOrderId") REFERENCES "inventory"."AssemblyOrder"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."PurchaseOrder" ADD CONSTRAINT "PurchaseOrder_supplierId_fkey" FOREIGN KEY ("supplierId") REFERENCES "inventory"."Supplier"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."PurchaseOrderLine" ADD CONSTRAINT "PurchaseOrderLine_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "inventory"."PurchaseOrder"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."PurchaseOrderLine" ADD CONSTRAINT "PurchaseOrderLine_itemId_fkey" FOREIGN KEY ("itemId") REFERENCES "inventory"."Item"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."Sku" ADD CONSTRAINT "Sku_dimensionsId_fkey" FOREIGN KEY ("dimensionsId") REFERENCES "inventory"."Dimensions"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."Sku" ADD CONSTRAINT "Sku_locationId_fkey" FOREIGN KEY ("locationId") REFERENCES "inventory"."WarehouseLocation"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."Sku" ADD CONSTRAINT "Sku_productId_fkey" FOREIGN KEY ("productId") REFERENCES "inventory"."Product"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."AmazonProduct" ADD CONSTRAINT "AmazonProduct_dimensionsId_fkey" FOREIGN KEY ("dimensionsId") REFERENCES "inventory"."Dimensions"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."AmazonProduct" ADD CONSTRAINT "AmazonProduct_skuId_fkey" FOREIGN KEY ("skuId") REFERENCES "inventory"."Sku"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."AmazonProduct" ADD CONSTRAINT "AmazonProduct_productItemId_fkey" FOREIGN KEY ("productItemId") REFERENCES "inventory"."Product"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."AmazonSalesData" ADD CONSTRAINT "AmazonSalesData_fbaProductId_fkey" FOREIGN KEY ("fbaProductId") REFERENCES "inventory"."AmazonProduct"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."Shipment" ADD CONSTRAINT "Shipment_movementId_fkey" FOREIGN KEY ("movementId") REFERENCES "inventory"."Movement"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."Shipment" ADD CONSTRAINT "Shipment_productId_fkey" FOREIGN KEY ("productId") REFERENCES "inventory"."Product"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."ShipmentLine" ADD CONSTRAINT "ShipmentLine_lotId_fkey" FOREIGN KEY ("lotId") REFERENCES "inventory"."InventoryLot"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."ShipmentLine" ADD CONSTRAINT "ShipmentLine_shipmentId_fkey" FOREIGN KEY ("shipmentId") REFERENCES "inventory"."Shipment"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."ShipmentLine" ADD CONSTRAINT "ShipmentLine_skuId_fkey" FOREIGN KEY ("skuId") REFERENCES "inventory"."Sku"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."_ItemToItemPart" ADD CONSTRAINT "_ItemToItemPart_A_fkey" FOREIGN KEY ("A") REFERENCES "inventory"."Item"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."_ItemToItemPart" ADD CONSTRAINT "_ItemToItemPart_B_fkey" FOREIGN KEY ("B") REFERENCES "inventory"."ProductPart"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."_ItemToProjectThreeMFFile" ADD CONSTRAINT "_ItemToProjectThreeMFFile_A_fkey" FOREIGN KEY ("A") REFERENCES "inventory"."Item"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."_ItemToProjectThreeMFFile" ADD CONSTRAINT "_ItemToProjectThreeMFFile_B_fkey" FOREIGN KEY ("B") REFERENCES "print-farm"."ProjectThreeMFFile"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."_ItemToProductionJob" ADD CONSTRAINT "_ItemToProductionJob_A_fkey" FOREIGN KEY ("A") REFERENCES "inventory"."Item"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."_ItemToProductionJob" ADD CONSTRAINT "_ItemToProductionJob_B_fkey" FOREIGN KEY ("B") REFERENCES "print-farm"."ProductionJob"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."_ItemToPrintRun" ADD CONSTRAINT "_ItemToPrintRun_A_fkey" FOREIGN KEY ("A") REFERENCES "inventory"."Item"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."_ItemToPrintRun" ADD CONSTRAINT "_ItemToPrintRun_B_fkey" FOREIGN KEY ("B") REFERENCES "print-farm"."PrintRun"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."_SpareParts" ADD CONSTRAINT "_SpareParts_A_fkey" FOREIGN KEY ("A") REFERENCES "inventory"."CompatibleMachine"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."_SpareParts" ADD CONSTRAINT "_SpareParts_B_fkey" FOREIGN KEY ("B") REFERENCES "inventory"."Item"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."_ProjectRelatedSku" ADD CONSTRAINT "_ProjectRelatedSku_A_fkey" FOREIGN KEY ("A") REFERENCES "print-farm"."ProjectThreeMFFile"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."_ProjectRelatedSku" ADD CONSTRAINT "_ProjectRelatedSku_B_fkey" FOREIGN KEY ("B") REFERENCES "inventory"."Sku"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."_JobsToFiles" ADD CONSTRAINT "_JobsToFiles_A_fkey" FOREIGN KEY ("A") REFERENCES "print-farm"."ProductionJob"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."_JobsToFiles" ADD CONSTRAINT "_JobsToFiles_B_fkey" FOREIGN KEY ("B") REFERENCES "print-farm"."ProjectThreeMFFile"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."_ProductionJobParts" ADD CONSTRAINT "_ProductionJobParts_A_fkey" FOREIGN KEY ("A") REFERENCES "print-farm"."ProductionJob"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."_ProductionJobParts" ADD CONSTRAINT "_ProductionJobParts_B_fkey" FOREIGN KEY ("B") REFERENCES "print-farm"."ProjectPart"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."_PrinterCompatibility" ADD CONSTRAINT "_PrinterCompatibility_A_fkey" FOREIGN KEY ("A") REFERENCES "print-farm"."Printer"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."_PrinterCompatibility" ADD CONSTRAINT "_PrinterCompatibility_B_fkey" FOREIGN KEY ("B") REFERENCES "print-farm"."PrinterMacro"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."_PrinterModelMacroCompatibility" ADD CONSTRAINT "_PrinterModelMacroCompatibility_A_fkey" FOREIGN KEY ("A") REFERENCES "print-farm"."PrinterMacro"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."_PrinterModelMacroCompatibility" ADD CONSTRAINT "_PrinterModelMacroCompatibility_B_fkey" FOREIGN KEY ("B") REFERENCES "print-farm"."PrinterModel"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."_PrinterModelErrorCode" ADD CONSTRAINT "_PrinterModelErrorCode_A_fkey" FOREIGN KEY ("A") REFERENCES "print-farm"."ErrorCode"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."_PrinterModelErrorCode" ADD CONSTRAINT "_PrinterModelErrorCode_B_fkey" FOREIGN KEY ("B") REFERENCES "print-farm"."PrinterModel"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."_OdetteToProductionJob" ADD CONSTRAINT "_OdetteToProductionJob_A_fkey" FOREIGN KEY ("A") REFERENCES "inventory"."Odette"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."_OdetteToProductionJob" ADD CONSTRAINT "_OdetteToProductionJob_B_fkey" FOREIGN KEY ("B") REFERENCES "print-farm"."ProductionJob"("id") ON DELETE CASCADE ON UPDATE CASCADE;
