-- Consigli AI Panoramica: elaborazione in background e costo della richiesta (28/10/2026).
-- Solo colonne nuove; le righe esistenti restano `done`.

ALTER TABLE "product"."OverviewAiInsight"
    ADD COLUMN "status" TEXT NOT NULL DEFAULT 'done',
    ADD COLUMN "error" TEXT,
    ADD COLUMN "inputTokens" INTEGER,
    ADD COLUMN "cachedInputTokens" INTEGER,
    ADD COLUMN "outputTokens" INTEGER,
    ADD COLUMN "reasoningTokens" INTEGER,
    ADD COLUMN "costUsd" DOUBLE PRECISION,
    ADD COLUMN "costEur" DOUBLE PRECISION,
    ADD COLUMN "completedAt" TIMESTAMPTZ(6);
