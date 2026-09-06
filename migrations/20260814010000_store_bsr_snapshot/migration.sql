-- Snapshot giornaliero BSR: SP-API non espone lo storico, lo costruiamo noi.
CREATE TABLE "product"."StoreBsrSnapshot" (
    "id" TEXT NOT NULL,
    "channel" "product"."StoreChannel" NOT NULL,
    "storeKey" TEXT NOT NULL,
    "asin" TEXT NOT NULL,
    "sku" TEXT,
    "capturedAt" DATE NOT NULL,
    "category" TEXT NOT NULL,
    "categoryKey" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "rank" INTEGER NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "StoreBsrSnapshot_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "StoreBsrSnapshot_rank_key" ON "product"."StoreBsrSnapshot"("channel", "storeKey", "asin", "capturedAt", "kind", "categoryKey");

CREATE INDEX "StoreBsrSnapshot_asin_store_date" ON "product"."StoreBsrSnapshot"("asin", "storeKey", "capturedAt");
