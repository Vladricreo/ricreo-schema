-- Credenziali OAuth Gmail Workspace per messaggistica Amazon via email forwarding
CREATE TABLE "product"."GmailOAuthCredential" (
    "id" TEXT NOT NULL,
    "mailboxEmail" TEXT NOT NULL,
    "accessToken" TEXT NOT NULL,
    "refreshToken" TEXT NOT NULL,
    "expiresAt" TIMESTAMPTZ(6) NOT NULL,
    "scopes" TEXT NOT NULL DEFAULT '',
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "GmailOAuthCredential_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "GmailOAuthCredential_mailboxEmail_key" ON "product"."GmailOAuthCredential"("mailboxEmail");
