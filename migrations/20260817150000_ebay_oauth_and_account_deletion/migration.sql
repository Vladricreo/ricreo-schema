-- Credenziali OAuth eBay (access + refresh) cifrate a riposo
CREATE TABLE "product"."EbayOAuthCredential" (
    "id" TEXT NOT NULL,
    "accountKey" TEXT NOT NULL,
    "accessToken" TEXT NOT NULL,
    "refreshToken" TEXT NOT NULL,
    "expiresAt" TIMESTAMPTZ(6) NOT NULL,
    "scopes" TEXT NOT NULL DEFAULT '',
    "ebayUserId" TEXT,
    "ebayUsername" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "EbayOAuthCredential_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "EbayOAuthCredential_accountKey_key" ON "product"."EbayOAuthCredential"("accountKey");

-- Eventi Marketplace Account Deletion (ingress Edge Function)
CREATE TABLE "product"."EbayAccountDeletion" (
    "id" TEXT NOT NULL,
    "notificationId" TEXT NOT NULL,
    "topic" TEXT NOT NULL DEFAULT 'MARKETPLACE_ACCOUNT_DELETION',
    "eventDate" TIMESTAMPTZ(6),
    "usernameEnc" TEXT,
    "userIdEnc" TEXT,
    "eiasTokenEnc" TEXT,
    "payloadEnc" TEXT NOT NULL,
    "signatureValid" BOOLEAN NOT NULL DEFAULT false,
    "processedAt" TIMESTAMPTZ(6),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "EbayAccountDeletion_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "EbayAccountDeletion_notificationId_key" ON "product"."EbayAccountDeletion"("notificationId");
CREATE INDEX "EbayAccountDeletion_processedAt_idx" ON "product"."EbayAccountDeletion"("processedAt");
CREATE INDEX "EbayAccountDeletion_createdAt_idx" ON "product"."EbayAccountDeletion"("createdAt");
