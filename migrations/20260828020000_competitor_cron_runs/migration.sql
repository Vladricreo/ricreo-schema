-- Avanzamento giornaliero delle cron concorrenti (listing eBay mancanti,
-- QuantitySold eBay, BSR/prezzo Amazon). Solo schema product.

DO $$
BEGIN
    CREATE TYPE "product"."CompetitorCronJob" AS ENUM ('EBAY_LISTINGS', 'EBAY_SOLD', 'AMAZON_LISTINGS');
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS "product"."CompetitorCronRun" (
    "id" TEXT NOT NULL,
    "job" "product"."CompetitorCronJob" NOT NULL,
    "runOn" DATE NOT NULL,
    "cursor" TEXT,
    "processed" INTEGER NOT NULL DEFAULT 0,
    "total" INTEGER NOT NULL DEFAULT 0,
    "skipped" INTEGER NOT NULL DEFAULT 0,
    "changed" INTEGER NOT NULL DEFAULT 0,
    "complete" BOOLEAN NOT NULL DEFAULT false,
    "message" TEXT,
    "errors" JSONB,
    "startedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CompetitorCronRun_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "CompetitorCronRun_job_runOn_key"
    ON "product"."CompetitorCronRun"("job", "runOn");

CREATE INDEX IF NOT EXISTS "CompetitorCronRun_job_runOn_idx"
    ON "product"."CompetitorCronRun"("job", "runOn" DESC);
