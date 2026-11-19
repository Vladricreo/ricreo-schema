-- Conversazioni Amazon chiuse a mano dalla console (gestite)
ALTER TABLE "product"."AmazonBuyerConversationRead"
    ADD COLUMN "closedAt" TIMESTAMPTZ(6),
    ADD COLUMN "closedByName" TEXT,
    ADD COLUMN "closedInboundMessageId" TEXT;
