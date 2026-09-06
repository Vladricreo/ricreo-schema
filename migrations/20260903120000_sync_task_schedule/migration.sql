-- Coda prioritaria del tick vendite (cron 30s). Solo schema product.

CREATE TABLE "product"."SyncTaskSchedule" (
    "id" TEXT NOT NULL,
    "pipeline" TEXT NOT NULL,
    "channel" "product"."StoreChannel" NOT NULL,
    "kind" TEXT NOT NULL,
    "scopeKey" TEXT NOT NULL DEFAULT '',
    "priority" INTEGER NOT NULL DEFAULT 100,
    "intervalMs" INTEGER NOT NULL,
    "nextRunAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "runningUntil" TIMESTAMPTZ(6),
    "ownerId" TEXT,
    "lastRunAt" TIMESTAMPTZ(6),
    "lastOkAt" TIMESTAMPTZ(6),
    "failures" INTEGER NOT NULL DEFAULT 0,
    "lastMessage" TEXT,
    "enabled" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SyncTaskSchedule_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "SyncTaskSchedule_key" ON "product"."SyncTaskSchedule" ("pipeline", "channel", "kind", "scopeKey");

CREATE INDEX "SyncTaskSchedule_due" ON "product"."SyncTaskSchedule" ("enabled", "nextRunAt", "priority");
