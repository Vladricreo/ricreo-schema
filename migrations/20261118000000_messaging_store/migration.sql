-- Messaggistica salvata a DB: il cron `messaggistica` legge Gmail (Amazon, Help) ed eBay
-- ogni 5 minuti e le pagine leggono da queste tabelle, non dalle piattaforme.

ALTER TABLE "product"."MessagingSentReply" ADD COLUMN "authorKind" TEXT NOT NULL DEFAULT 'operator';

CREATE TABLE "product"."MessagingConversation" (
    "id" TEXT NOT NULL,
    "channel" TEXT NOT NULL,
    "kind" TEXT NOT NULL DEFAULT '',
    "externalId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "preview" TEXT NOT NULL DEFAULT '',
    "lastMessageAt" TIMESTAMPTZ(6),
    "unreadCount" INTEGER NOT NULL DEFAULT 0,
    "status" TEXT,
    "orderIds" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "data" JSONB NOT NULL,
    "contentHash" TEXT NOT NULL,
    "sourceHash" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "MessagingConversation_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "MessagingConversation_external" ON "product"."MessagingConversation"("channel", "kind", "externalId");
CREATE INDEX "MessagingConversation_recent" ON "product"."MessagingConversation"("channel", "kind", "lastMessageAt");

CREATE TABLE "product"."MessagingMessage" (
    "id" TEXT NOT NULL,
    "conversationId" TEXT NOT NULL,
    "externalId" TEXT NOT NULL,
    "threadId" TEXT,
    "position" INTEGER NOT NULL,
    "direction" TEXT NOT NULL,
    "authorKind" TEXT NOT NULL,
    "authorUserId" INTEGER,
    "authorName" TEXT,
    "body" TEXT NOT NULL,
    "sentAt" TIMESTAMPTZ(6),
    "data" JSONB NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "MessagingMessage_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "MessagingMessage_external" ON "product"."MessagingMessage"("conversationId", "externalId");
CREATE INDEX "MessagingMessage_order" ON "product"."MessagingMessage"("conversationId", "position");

ALTER TABLE "product"."MessagingMessage"
    ADD CONSTRAINT "MessagingMessage_conversationId_fkey" FOREIGN KEY ("conversationId")
    REFERENCES "product"."MessagingConversation"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "product"."MessagingGmailThread" (
    "id" TEXT NOT NULL,
    "mailbox" TEXT NOT NULL,
    "threadId" TEXT NOT NULL,
    "historyId" TEXT NOT NULL,
    "lastMessageAt" TIMESTAMPTZ(6),
    "data" JSONB NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "MessagingGmailThread_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "MessagingGmailThread_thread" ON "product"."MessagingGmailThread"("mailbox", "threadId");
CREATE INDEX "MessagingGmailThread_recent" ON "product"."MessagingGmailThread"("mailbox", "lastMessageAt");

CREATE TABLE "product"."MessagingSyncState" (
    "key" TEXT NOT NULL,
    "version" INTEGER NOT NULL DEFAULT 0,
    "pendingRebuild" BOOLEAN NOT NULL DEFAULT false,
    "lockedUntil" TIMESTAMPTZ(6),
    "lastRunAt" TIMESTAMPTZ(6),
    "lastOkAt" TIMESTAMPTZ(6),
    "lastFullAt" TIMESTAMPTZ(6),
    "lastError" TEXT,
    "info" JSONB,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "MessagingSyncState_pkey" PRIMARY KEY ("key")
);
