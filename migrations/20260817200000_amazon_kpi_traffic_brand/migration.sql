-- KPI Amazon: traffico Sales and Traffic + funnel Brand Analytics.
-- optionKey sui job report per batch SQP senza collidere sulla stessa settimana.

ALTER TABLE "product"."StoreReportJob"
  ADD COLUMN IF NOT EXISTS "optionKey" TEXT NOT NULL DEFAULT '';

DROP INDEX IF EXISTS "product"."StoreReportJob_window_key";

CREATE UNIQUE INDEX "StoreReportJob_window_key"
  ON "product"."StoreReportJob" ("channel", "reportType", "storeKey", "optionKey", "dataStart", "dataEnd");

CREATE TABLE IF NOT EXISTS "product"."StoreTrafficDaily" (
  "id" TEXT NOT NULL,
  "channel" "product"."StoreChannel" NOT NULL,
  "storeKey" TEXT NOT NULL,
  "sku" TEXT NOT NULL,
  "date" DATE NOT NULL,
  "asin" TEXT,
  "parentAsin" TEXT,
  "sessions" INTEGER NOT NULL DEFAULT 0,
  "pageViews" INTEGER NOT NULL DEFAULT 0,
  "buyBoxPercentage" DECIMAL(7,4),
  "unitSessionPercentage" DECIMAL(7,4),
  "unitsOrdered" INTEGER NOT NULL DEFAULT 0,
  "orderedProductSales" DECIMAL(12,2) NOT NULL DEFAULT 0,
  "totalOrderItems" INTEGER NOT NULL DEFAULT 0,
  "averageSellingPrice" DECIMAL(12,2),
  "currency" TEXT NOT NULL DEFAULT 'EUR',
  "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMPTZ(6) NOT NULL,

  CONSTRAINT "StoreTrafficDaily_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "StoreTrafficDaily_day_key"
  ON "product"."StoreTrafficDaily" ("channel", "storeKey", "sku", "date");
CREATE INDEX IF NOT EXISTS "StoreTrafficDaily_sku_date_idx"
  ON "product"."StoreTrafficDaily" ("sku", "date");
CREATE INDEX IF NOT EXISTS "StoreTrafficDaily_channel_date_idx"
  ON "product"."StoreTrafficDaily" ("channel", "date");
CREATE INDEX IF NOT EXISTS "StoreTrafficDaily_channel_sku_date_idx"
  ON "product"."StoreTrafficDaily" ("channel", "sku", "date");
CREATE INDEX IF NOT EXISTS "StoreTrafficDaily_asin_date_idx"
  ON "product"."StoreTrafficDaily" ("asin", "date");

CREATE TABLE IF NOT EXISTS "product"."StoreSearchCatalogPeriod" (
  "id" TEXT NOT NULL,
  "channel" "product"."StoreChannel" NOT NULL,
  "storeKey" TEXT NOT NULL,
  "asin" TEXT NOT NULL,
  "periodType" TEXT NOT NULL,
  "startDate" DATE NOT NULL,
  "endDate" DATE NOT NULL,
  "impressionCount" INTEGER NOT NULL DEFAULT 0,
  "clickCount" INTEGER NOT NULL DEFAULT 0,
  "clickRate" DECIMAL(7,4),
  "cartAddCount" INTEGER NOT NULL DEFAULT 0,
  "purchaseCount" INTEGER NOT NULL DEFAULT 0,
  "conversionRate" DECIMAL(7,4),
  "searchTrafficSales" DECIMAL(12,2) NOT NULL DEFAULT 0,
  "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMPTZ(6) NOT NULL,

  CONSTRAINT "StoreSearchCatalogPeriod_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "StoreSearchCatalog_period_key"
  ON "product"."StoreSearchCatalogPeriod" ("channel", "storeKey", "asin", "periodType", "startDate");
CREATE INDEX IF NOT EXISTS "StoreSearchCatalogPeriod_channel_storeKey_startDate_idx"
  ON "product"."StoreSearchCatalogPeriod" ("channel", "storeKey", "startDate");
CREATE INDEX IF NOT EXISTS "StoreSearchCatalogPeriod_asin_startDate_idx"
  ON "product"."StoreSearchCatalogPeriod" ("asin", "startDate");

CREATE TABLE IF NOT EXISTS "product"."StoreSearchQueryPeriod" (
  "id" TEXT NOT NULL,
  "channel" "product"."StoreChannel" NOT NULL,
  "storeKey" TEXT NOT NULL,
  "asin" TEXT NOT NULL,
  "searchQuery" TEXT NOT NULL,
  "periodType" TEXT NOT NULL,
  "startDate" DATE NOT NULL,
  "endDate" DATE NOT NULL,
  "searchQueryScore" DECIMAL(12,4),
  "searchQueryVolume" INTEGER NOT NULL DEFAULT 0,
  "totalQueryImpressionCount" INTEGER NOT NULL DEFAULT 0,
  "asinImpressionCount" INTEGER NOT NULL DEFAULT 0,
  "asinImpressionShare" DECIMAL(7,4),
  "totalClickCount" INTEGER NOT NULL DEFAULT 0,
  "asinClickCount" INTEGER NOT NULL DEFAULT 0,
  "asinClickShare" DECIMAL(7,4),
  "totalCartAddCount" INTEGER NOT NULL DEFAULT 0,
  "asinCartAddCount" INTEGER NOT NULL DEFAULT 0,
  "asinCartAddShare" DECIMAL(7,4),
  "totalPurchaseCount" INTEGER NOT NULL DEFAULT 0,
  "asinPurchaseCount" INTEGER NOT NULL DEFAULT 0,
  "asinPurchaseShare" DECIMAL(7,4),
  "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMPTZ(6) NOT NULL,

  CONSTRAINT "StoreSearchQueryPeriod_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "StoreSearchQuery_period_key"
  ON "product"."StoreSearchQueryPeriod" ("channel", "storeKey", "asin", "searchQuery", "periodType", "startDate");
CREATE INDEX IF NOT EXISTS "StoreSearchQueryPeriod_channel_storeKey_startDate_idx"
  ON "product"."StoreSearchQueryPeriod" ("channel", "storeKey", "startDate");
CREATE INDEX IF NOT EXISTS "StoreSearchQueryPeriod_searchQuery_idx"
  ON "product"."StoreSearchQueryPeriod" ("searchQuery");
CREATE INDEX IF NOT EXISTS "StoreSearchQueryPeriod_asin_startDate_idx"
  ON "product"."StoreSearchQueryPeriod" ("asin", "startDate");
