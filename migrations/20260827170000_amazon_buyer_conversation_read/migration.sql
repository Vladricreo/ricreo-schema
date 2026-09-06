-- Stato letto conversazioni Amazon (inbox Gmail gruppo)
CREATE TABLE "product"."AmazonBuyerConversationRead" (
    "id" TEXT NOT NULL,
    "conversationId" TEXT NOT NULL,
    "isRead" BOOLEAN NOT NULL DEFAULT true,
    "readAt" TIMESTAMPTZ(6),
    "readByUserId" INTEGER,
    "readByName" TEXT,
    "lastInboundMessageId" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "AmazonBuyerConversationRead_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "AmazonBuyerConversationRead_conv" ON "product"."AmazonBuyerConversationRead"("conversationId");
CREATE INDEX "AmazonBuyerConversationRead_read" ON "product"."AmazonBuyerConversationRead"("isRead");
