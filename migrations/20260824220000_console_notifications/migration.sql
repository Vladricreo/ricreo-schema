-- Inbox Product Console: solo schema product.
-- Non tocca public.Notification né print-farm.

CREATE TYPE "product"."ConsoleNotificationSeverity" AS ENUM ('INFO', 'SUCCESS', 'WARNING', 'ERROR');

CREATE TYPE "product"."ConsoleNotificationTopic" AS ENUM (
  'SYSTEM',
  'QUALITY_REVIEW',
  'QUALITY_LISTING',
  'COMPETITOR',
  'COMPETITOR_LISTING',
  'COMPETITOR_REVIEW',
  'AMAZON_CLAIM',
  'PROFIT',
  'LISTING',
  'PRODUCT',
  'SALES',
  'FBA_INVENTORY',
  'IMPROVEMENT',
  'CROSSPLATFORM',
  'MESSAGING'
);

CREATE TYPE "product"."ConsoleNotificationEntityKind" AS ENUM (
  'LISTING',
  'PRODUCT',
  'REVIEW',
  'INACTIVITY_PERIOD',
  'COMPETITOR',
  'COMPETITOR_LISTING',
  'COMPETITOR_REVIEW',
  'AMAZON_CLAIM',
  'PROFIT_ESTIMATE',
  'IMPROVEMENT_TASK',
  'POINT_IN_TIME',
  'SALES_ORDER',
  'FBA_INVENTORY',
  'CROSSPLATFORM_LINK'
);

CREATE TABLE IF NOT EXISTS "product"."ConsoleNotification" (
    "id" TEXT NOT NULL,
    "topic" "product"."ConsoleNotificationTopic" NOT NULL,
    "severity" "product"."ConsoleNotificationSeverity" NOT NULL DEFAULT 'INFO',
    "title" TEXT NOT NULL,
    "body" TEXT,
    "url" TEXT,
    "imageUrl" TEXT,
    "countryCode" TEXT,
    "countryName" TEXT,
    "channel" "product"."StoreChannel",
    "storeKey" TEXT,
    "sku" TEXT,
    "asin" TEXT,
    "marketplaceId" TEXT,
    "listingId" TEXT,
    "rating" INTEGER,
    "author" TEXT,
    "inventoryProductId" UUID,
    "reviewId" TEXT,
    "inactivityPeriodId" TEXT,
    "competitorId" TEXT,
    "competitorProductId" TEXT,
    "competitorReviewId" TEXT,
    "claimId" TEXT,
    "profitEstimateId" TEXT,
    "improvementTaskId" TEXT,
    "crossplatformLinkId" TEXT,
    "pointInTimeId" TEXT,
    "createdByUserId" INTEGER,
    "data" JSONB,
    "dedupeKey" TEXT,
    "expiresAt" TIMESTAMPTZ(6),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ConsoleNotification_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "product"."ConsoleNotificationLink" (
    "id" TEXT NOT NULL,
    "notificationId" TEXT NOT NULL,
    "kind" "product"."ConsoleNotificationEntityKind" NOT NULL,
    "entityId" TEXT NOT NULL,
    "isPrimary" BOOLEAN NOT NULL DEFAULT false,
    "label" TEXT,
    "url" TEXT,
    "imageUrl" TEXT,
    "channel" "product"."StoreChannel",
    "storeKey" TEXT,
    "sku" TEXT,
    "asin" TEXT,
    "marketplaceId" TEXT,
    "countryCode" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ConsoleNotificationLink_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "product"."ConsoleNotificationRecipient" (
    "id" TEXT NOT NULL,
    "notificationId" TEXT NOT NULL,
    "userId" INTEGER NOT NULL,
    "isRead" BOOLEAN NOT NULL DEFAULT false,
    "readAt" TIMESTAMPTZ(6),
    "archivedAt" TIMESTAMPTZ(6),
    "deliveredAt" TIMESTAMPTZ(6),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ConsoleNotificationRecipient_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "product"."ConsoleNotificationPreference" (
    "id" TEXT NOT NULL,
    "userId" INTEGER NOT NULL,
    "topic" "product"."ConsoleNotificationTopic" NOT NULL,
    "enabled" BOOLEAN NOT NULL DEFAULT true,
    "minSeverity" "product"."ConsoleNotificationSeverity" NOT NULL DEFAULT 'INFO',
    "inApp" BOOLEAN NOT NULL DEFAULT true,
    "email" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ConsoleNotificationPreference_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "ConsoleNotification_dedupeKey_key"
  ON "product"."ConsoleNotification"("dedupeKey");

CREATE INDEX IF NOT EXISTS "ConsoleNotification_topic_idx"
  ON "product"."ConsoleNotification"("topic");

CREATE INDEX IF NOT EXISTS "ConsoleNotification_severity_idx"
  ON "product"."ConsoleNotification"("severity");

CREATE INDEX IF NOT EXISTS "ConsoleNotification_createdAt_idx"
  ON "product"."ConsoleNotification"("createdAt" DESC);

CREATE INDEX IF NOT EXISTS "ConsoleNotification_createdByUserId_idx"
  ON "product"."ConsoleNotification"("createdByUserId");

CREATE INDEX IF NOT EXISTS "ConsoleNotification_expiresAt_idx"
  ON "product"."ConsoleNotification"("expiresAt");

CREATE INDEX IF NOT EXISTS "ConsoleNotification_channel_sku_idx"
  ON "product"."ConsoleNotification"("channel", "sku");

CREATE INDEX IF NOT EXISTS "ConsoleNotification_asin_idx"
  ON "product"."ConsoleNotification"("asin");

CREATE INDEX IF NOT EXISTS "ConsoleNotification_inventoryProductId_idx"
  ON "product"."ConsoleNotification"("inventoryProductId");

CREATE INDEX IF NOT EXISTS "ConsoleNotificationLink_notificationId_idx"
  ON "product"."ConsoleNotificationLink"("notificationId");

CREATE INDEX IF NOT EXISTS "ConsoleNotificationLink_kind_entityId_idx"
  ON "product"."ConsoleNotificationLink"("kind", "entityId");

CREATE UNIQUE INDEX IF NOT EXISTS "ConsoleNotificationRecipient_notificationId_userId_key"
  ON "product"."ConsoleNotificationRecipient"("notificationId", "userId");

CREATE INDEX IF NOT EXISTS "ConsoleNotificationRecipient_userId_isRead_idx"
  ON "product"."ConsoleNotificationRecipient"("userId", "isRead");

CREATE INDEX IF NOT EXISTS "ConsoleNotificationRecipient_userId_archivedAt_idx"
  ON "product"."ConsoleNotificationRecipient"("userId", "archivedAt");

CREATE INDEX IF NOT EXISTS "ConsoleNotificationRecipient_userId_createdAt_idx"
  ON "product"."ConsoleNotificationRecipient"("userId", "createdAt" DESC);

CREATE INDEX IF NOT EXISTS "ConsoleNotificationRecipient_notificationId_idx"
  ON "product"."ConsoleNotificationRecipient"("notificationId");

CREATE UNIQUE INDEX IF NOT EXISTS "ConsoleNotificationPreference_userId_topic_key"
  ON "product"."ConsoleNotificationPreference"("userId", "topic");

CREATE INDEX IF NOT EXISTS "ConsoleNotificationPreference_userId_idx"
  ON "product"."ConsoleNotificationPreference"("userId");

ALTER TABLE "product"."ConsoleNotification"
  ADD CONSTRAINT "ConsoleNotification_reviewId_fkey"
  FOREIGN KEY ("reviewId") REFERENCES "product"."StoreCustomerReview"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "product"."ConsoleNotification"
  ADD CONSTRAINT "ConsoleNotification_inactivityPeriodId_fkey"
  FOREIGN KEY ("inactivityPeriodId") REFERENCES "product"."StoreListingInactivityPeriod"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "product"."ConsoleNotification"
  ADD CONSTRAINT "ConsoleNotification_competitorId_fkey"
  FOREIGN KEY ("competitorId") REFERENCES "product"."Competitor"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "product"."ConsoleNotification"
  ADD CONSTRAINT "ConsoleNotification_competitorProductId_fkey"
  FOREIGN KEY ("competitorProductId") REFERENCES "product"."CompetitorProduct"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "product"."ConsoleNotification"
  ADD CONSTRAINT "ConsoleNotification_competitorReviewId_fkey"
  FOREIGN KEY ("competitorReviewId") REFERENCES "product"."CompetitorCustomerReview"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "product"."ConsoleNotification"
  ADD CONSTRAINT "ConsoleNotification_claimId_fkey"
  FOREIGN KEY ("claimId") REFERENCES "product"."FbaMissingUnitClaim"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "product"."ConsoleNotification"
  ADD CONSTRAINT "ConsoleNotification_profitEstimateId_fkey"
  FOREIGN KEY ("profitEstimateId") REFERENCES "product"."ListingProfitEstimate"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "product"."ConsoleNotification"
  ADD CONSTRAINT "ConsoleNotification_improvementTaskId_fkey"
  FOREIGN KEY ("improvementTaskId") REFERENCES "product"."ImprovementTask"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "product"."ConsoleNotification"
  ADD CONSTRAINT "ConsoleNotification_crossplatformLinkId_fkey"
  FOREIGN KEY ("crossplatformLinkId") REFERENCES "product"."CrossplatformListingLink"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "product"."ConsoleNotification"
  ADD CONSTRAINT "ConsoleNotification_pointInTimeId_fkey"
  FOREIGN KEY ("pointInTimeId") REFERENCES "product"."PointInTime"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "product"."ConsoleNotification"
  ADD CONSTRAINT "ConsoleNotification_createdByUserId_fkey"
  FOREIGN KEY ("createdByUserId") REFERENCES "public"."User"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "product"."ConsoleNotificationLink"
  ADD CONSTRAINT "ConsoleNotificationLink_notificationId_fkey"
  FOREIGN KEY ("notificationId") REFERENCES "product"."ConsoleNotification"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "product"."ConsoleNotificationRecipient"
  ADD CONSTRAINT "ConsoleNotificationRecipient_notificationId_fkey"
  FOREIGN KEY ("notificationId") REFERENCES "product"."ConsoleNotification"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "product"."ConsoleNotificationRecipient"
  ADD CONSTRAINT "ConsoleNotificationRecipient_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "public"."User"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "product"."ConsoleNotificationPreference"
  ADD CONSTRAINT "ConsoleNotificationPreference_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "public"."User"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
