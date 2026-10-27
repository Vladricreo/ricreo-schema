-- Consigli AI della Panoramica (tab «Consigli AI», 27/10/2026).
-- Solo aggiunte: una tabella nuova. Nessun dato esistente cambia.

CREATE TABLE "product"."OverviewAiInsight" (
    "id" TEXT NOT NULL,
    "presetKey" TEXT,
    "question" TEXT NOT NULL,
    "period" TEXT NOT NULL,
    "answer" JSONB NOT NULL,
    "dataSnapshot" TEXT NOT NULL,
    "model" TEXT NOT NULL,
    "reasoningEffort" TEXT,
    "durationMs" INTEGER,
    "createdByUserId" INTEGER,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "OverviewAiInsight_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "OverviewAiInsight_createdAt_idx" ON "product"."OverviewAiInsight"("createdAt" DESC);

-- Letta solo via Prisma (postgres, proprietario): RLS senza policy chiude l'accesso anon.
ALTER TABLE "product"."OverviewAiInsight" ENABLE ROW LEVEL SECURITY;
