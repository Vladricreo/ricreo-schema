-- Periodi di inattività listing Amazon (BUYABLE/DISCOVERABLE).
-- Amazon non fornisce lo storico: lo ricostruiamo dagli snapshot giornalieri.
-- Solo schema product.

CREATE TABLE IF NOT EXISTS "product"."StoreListingActivitySnapshot" (
    "id" TEXT NOT NULL,
    "channel" "product"."StoreChannel" NOT NULL,
    "storeKey" TEXT NOT NULL,
    "countryCode" TEXT NOT NULL,
    "sku" TEXT NOT NULL,
    "asin" TEXT,
    "capturedAt" DATE NOT NULL,
    "observedAt" TIMESTAMPTZ(6) NOT NULL,
    "isPublished" BOOLEAN NOT NULL,
    "isBuyable" BOOLEAN NOT NULL,
    "isDiscoverable" BOOLEAN NOT NULL,
    "statuses" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    "quantity" INTEGER,
    "amazonUpdatedAt" TIMESTAMPTZ(6),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "StoreListingActivitySnapshot_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "StoreListingActivity_day_key"
  ON "product"."StoreListingActivitySnapshot" ("channel", "storeKey", "sku", "capturedAt");

CREATE INDEX IF NOT EXISTS "StoreListingActivity_sku_date"
  ON "product"."StoreListingActivitySnapshot" ("sku", "storeKey", "capturedAt");

CREATE TABLE IF NOT EXISTS "product"."StoreListingInactivityPeriod" (
    "id" TEXT NOT NULL,
    "channel" "product"."StoreChannel" NOT NULL,
    "storeKey" TEXT NOT NULL,
    "countryCode" TEXT NOT NULL,
    "sku" TEXT NOT NULL,
    "asin" TEXT,
    "startedAt" TIMESTAMPTZ(6) NOT NULL,
    "endedAt" TIMESTAMPTZ(6),
    "reason" TEXT NOT NULL,
    "statuses" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    "quantity" INTEGER,
    "amazonUpdatedAt" TIMESTAMPTZ(6),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "StoreListingInactivityPeriod_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "StoreListingInactivity_sku_start"
  ON "product"."StoreListingInactivityPeriod" ("channel", "storeKey", "sku", "startedAt");

CREATE INDEX IF NOT EXISTS "StoreListingInactivity_open"
  ON "product"."StoreListingInactivityPeriod" ("sku", "storeKey", "endedAt");

CREATE UNIQUE INDEX IF NOT EXISTS "StoreListingInactivity_one_open"
  ON "product"."StoreListingInactivityPeriod" ("channel", "storeKey", "sku")
  WHERE "endedAt" IS NULL;
