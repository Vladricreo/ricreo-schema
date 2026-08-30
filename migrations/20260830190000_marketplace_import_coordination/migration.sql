-- Coordinamento import marketplace: quota API condivisa, lease di esecuzione
-- e topic inbox IMPORT. Solo schema product.

ALTER TYPE "product"."ConsoleNotificationTopic" ADD VALUE IF NOT EXISTS 'IMPORT';

CREATE TABLE IF NOT EXISTS "product"."ExternalApiQuotaGate" (
  "id"             TEXT           NOT NULL,
  "provider"       TEXT           NOT NULL,
  "scope"          TEXT           NOT NULL,
  "operationGroup" TEXT           NOT NULL,
  "nextSlotAt"     TIMESTAMPTZ(6) NOT NULL,
  "cooldownUntil"  TIMESTAMPTZ(6),
  "rate"           DOUBLE PRECISION NOT NULL DEFAULT 1,
  "lastGrantedAt"  TIMESTAMPTZ(6),
  "createdAt"      TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt"      TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "ExternalApiQuotaGate_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "ExternalApiQuotaGate_key"
  ON "product"."ExternalApiQuotaGate" ("provider", "scope", "operationGroup");

CREATE INDEX IF NOT EXISTS "ExternalApiQuotaGate_slot"
  ON "product"."ExternalApiQuotaGate" ("nextSlotAt");

CREATE TABLE IF NOT EXISTS "product"."ImportExecutionLease" (
  "id"        TEXT           NOT NULL,
  "pipeline"  TEXT           NOT NULL,
  "channel"   "product"."StoreChannel" NOT NULL,
  "storeKey"  TEXT           NOT NULL DEFAULT '',
  "rangeKey"  TEXT           NOT NULL DEFAULT '',
  "ownerId"   TEXT           NOT NULL,
  "expiresAt" TIMESTAMPTZ(6) NOT NULL,
  "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "ImportExecutionLease_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "ImportExecutionLease_key"
  ON "product"."ImportExecutionLease" ("pipeline", "channel", "storeKey", "rangeKey");

CREATE INDEX IF NOT EXISTS "ImportExecutionLease_expires"
  ON "product"."ImportExecutionLease" ("expiresAt");
