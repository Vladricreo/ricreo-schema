-- Messaggistica: bozze AI preparate dal cron all'arrivo del messaggio del cliente e
-- «note apprese» proposte dal confronto tra bozza AI e risposta inviata dall'operatore.
-- Nessuna risposta parte da sola: l'operatore rivede la bozza e la invia.

CREATE TABLE "product"."MessagingAiDraft" (
    "id" TEXT NOT NULL,
    "channel" TEXT NOT NULL,
    "conversationKey" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "trigger" TEXT NOT NULL DEFAULT 'auto',
    "requestedBy" TEXT,
    "basedOnMessageId" TEXT,
    "replyText" TEXT,
    "replyPreviewIt" TEXT,
    "customerLanguage" TEXT,
    "model" TEXT,
    "inputTokens" INTEGER,
    "cachedInputTokens" INTEGER,
    "outputTokens" INTEGER,
    "reasoningTokens" INTEGER,
    "error" TEXT,
    "outcome" TEXT,
    "outcomeSimilarity" DOUBLE PRECISION,
    "outcomeBy" TEXT,
    "outcomeAt" TIMESTAMPTZ(6),
    "completedAt" TIMESTAMPTZ(6),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "MessagingAiDraft_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "MessagingAiDraft_conversation" ON "product"."MessagingAiDraft"("channel", "conversationKey", "createdAt");
CREATE INDEX "MessagingAiDraft_status" ON "product"."MessagingAiDraft"("status", "createdAt");

CREATE TABLE "product"."MessagingAiNote" (
    "id" TEXT NOT NULL,
    "text" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "channel" TEXT,
    "sourceChannel" TEXT,
    "sourceKey" TEXT,
    "sourceDraftId" TEXT,
    "sentBy" TEXT,
    "decidedBy" TEXT,
    "decidedAt" TIMESTAMPTZ(6),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "MessagingAiNote_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "MessagingAiNote_status" ON "product"."MessagingAiNote"("status", "createdAt");
