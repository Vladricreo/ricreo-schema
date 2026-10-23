-- Risposte inviate dalla console: chi ha risposto, per l'avatar nella chat Amazon/eBay.
CREATE TABLE "product"."MessagingSentReply" (
    "id" TEXT NOT NULL,
    "channel" TEXT NOT NULL,
    "conversationKey" TEXT NOT NULL,
    "messageId" TEXT,
    "userId" INTEGER,
    "userName" TEXT,
    "textPreview" TEXT NOT NULL,
    "sentAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "MessagingSentReply_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "MessagingSentReply_conversation" ON "product"."MessagingSentReply"("channel", "conversationKey");
