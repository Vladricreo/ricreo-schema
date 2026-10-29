-- Analisi AI delle recensioni (Qualità › dettaglio, 29/10/2026).
-- Solo aggiunte: una tabella nuova. Nessun dato esistente cambia.

CREATE TABLE "product"."QualityReviewAnalysis" (
    "id" TEXT NOT NULL,
    "store" TEXT NOT NULL,
    "sku" TEXT NOT NULL,
    "marketplaceId" TEXT,
    "maxRating" INTEGER NOT NULL,
    "reviewLimit" INTEGER NOT NULL,
    "reviewCount" INTEGER NOT NULL,
    "answer" JSONB NOT NULL,
    "reviewsSnapshot" TEXT NOT NULL,
    "reviewIds" TEXT[],
    "model" TEXT NOT NULL,
    "reasoningEffort" TEXT,
    "durationMs" INTEGER,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "error" TEXT,
    "inputTokens" INTEGER,
    "cachedInputTokens" INTEGER,
    "outputTokens" INTEGER,
    "reasoningTokens" INTEGER,
    "costUsd" DOUBLE PRECISION,
    "costEur" DOUBLE PRECISION,
    "completedAt" TIMESTAMPTZ(6),
    "createdByUserId" INTEGER,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "QualityReviewAnalysis_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "QualityReviewAnalysis_store_sku_createdAt_idx"
    ON "product"."QualityReviewAnalysis"("store", "sku", "createdAt" DESC);

-- Letta solo via Prisma (postgres, proprietario): RLS senza policy chiude l'accesso anon.
ALTER TABLE "product"."QualityReviewAnalysis" ENABLE ROW LEVEL SECURITY;
