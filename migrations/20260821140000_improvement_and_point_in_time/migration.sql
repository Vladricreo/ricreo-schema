-- Task di miglioramento e point in time.
-- Solo schema product. Niente FK verso inventory.Product o public.users.

CREATE TYPE "product"."ImprovementTaskSource" AS ENUM (
  'NEGATIVE_REVIEWS',
  'GENERAL_PRODUCT',
  'OTHER'
);

CREATE TYPE "product"."ImprovementTaskStatus" AS ENUM (
  'OPEN',
  'IN_PROGRESS',
  'COMPLETED',
  'CANCELLED'
);

CREATE TYPE "product"."PointInTimeKind" AS ENUM (
  'LISTING_CHANGE',
  'PRODUCT_CHANGE',
  'PHOTO_CHANGE',
  'INFOGRAPHIC_CHANGE',
  'CUSTOMER_REVIEW',
  'SUPPLY_ISSUE',
  'FBA_STOCK_ZERO',
  'IMPROVEMENT_COMPLETED',
  'OTHER'
);

CREATE TYPE "product"."PointInTimeScope" AS ENUM (
  'LISTING',
  'STORE',
  'ASIN',
  'PRODUCT'
);

CREATE TABLE "product"."ImprovementTask" (
  "id" TEXT NOT NULL,
  "productId" UUID NOT NULL,
  "title" TEXT NOT NULL,
  "description" TEXT NOT NULL DEFAULT '',
  "source" "product"."ImprovementTaskSource" NOT NULL,
  "status" "product"."ImprovementTaskStatus" NOT NULL DEFAULT 'OPEN',
  "progressPercent" INTEGER NOT NULL DEFAULT 0,
  "characteristics" JSONB,
  "completedAt" TIMESTAMPTZ(6),
  "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "ImprovementTask_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "product"."ImprovementTaskAssignee" (
  "id" TEXT NOT NULL,
  "taskId" TEXT NOT NULL,
  "userId" INTEGER NOT NULL,
  "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "ImprovementTaskAssignee_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "product"."ImprovementTaskReview" (
  "id" TEXT NOT NULL,
  "taskId" TEXT NOT NULL,
  "reviewId" TEXT NOT NULL,
  "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "ImprovementTaskReview_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "product"."PointInTime" (
  "id" TEXT NOT NULL,
  "occurredAt" TIMESTAMPTZ(6) NOT NULL,
  "periodStart" DATE,
  "periodEnd" DATE,
  "kind" "product"."PointInTimeKind" NOT NULL,
  "scope" "product"."PointInTimeScope" NOT NULL,
  "title" TEXT NOT NULL,
  "description" TEXT NOT NULL DEFAULT '',
  "payload" JSONB NOT NULL,
  "destinationCountry" TEXT,
  "channel" "product"."StoreChannel",
  "storeKey" TEXT,
  "asin" TEXT,
  "sku" TEXT,
  "listingId" TEXT,
  "productId" UUID,
  "sourceTaskId" TEXT,
  "createdByUserId" INTEGER,
  "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "PointInTime_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "ImprovementTask_productId_idx" ON "product"."ImprovementTask"("productId");
CREATE INDEX "ImprovementTask_status_updatedAt_idx" ON "product"."ImprovementTask"("status", "updatedAt");
CREATE INDEX "ImprovementTask_source_idx" ON "product"."ImprovementTask"("source");

CREATE UNIQUE INDEX "ImprovementTaskAssignee_taskId_userId_key"
  ON "product"."ImprovementTaskAssignee"("taskId", "userId");
CREATE INDEX "ImprovementTaskAssignee_userId_idx" ON "product"."ImprovementTaskAssignee"("userId");

CREATE UNIQUE INDEX "ImprovementTaskReview_taskId_reviewId_key"
  ON "product"."ImprovementTaskReview"("taskId", "reviewId");
CREATE INDEX "ImprovementTaskReview_reviewId_idx" ON "product"."ImprovementTaskReview"("reviewId");

CREATE INDEX "PointInTime_occurredAt_idx" ON "product"."PointInTime"("occurredAt");
CREATE INDEX "PointInTime_kind_occurredAt_idx" ON "product"."PointInTime"("kind", "occurredAt");
CREATE INDEX "PointInTime_scope_occurredAt_idx" ON "product"."PointInTime"("scope", "occurredAt");
CREATE INDEX "PointInTime_productId_occurredAt_idx" ON "product"."PointInTime"("productId", "occurredAt");
CREATE INDEX "PointInTime_asin_occurredAt_idx" ON "product"."PointInTime"("asin", "occurredAt");
CREATE INDEX "PointInTime_sku_occurredAt_idx" ON "product"."PointInTime"("sku", "occurredAt");
CREATE INDEX "PointInTime_sourceTaskId_idx" ON "product"."PointInTime"("sourceTaskId");

ALTER TABLE "product"."ImprovementTaskAssignee"
  ADD CONSTRAINT "ImprovementTaskAssignee_taskId_fkey"
  FOREIGN KEY ("taskId") REFERENCES "product"."ImprovementTask"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "product"."ImprovementTaskReview"
  ADD CONSTRAINT "ImprovementTaskReview_taskId_fkey"
  FOREIGN KEY ("taskId") REFERENCES "product"."ImprovementTask"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "product"."PointInTime"
  ADD CONSTRAINT "PointInTime_sourceTaskId_fkey"
  FOREIGN KEY ("sourceTaskId") REFERENCES "product"."ImprovementTask"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;
