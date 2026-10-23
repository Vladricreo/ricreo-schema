-- Casi Amazon segnati come chiusi su Seller Central dalla console
ALTER TABLE "product"."AmazonBuyerConversationRead"
    ADD COLUMN "amazonClosedAt" TIMESTAMPTZ(6),
    ADD COLUMN "amazonClosedByName" TEXT,
    ADD COLUMN "amazonClosedInboundMessageId" TEXT;
