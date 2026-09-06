-- Credenziali OAuth Etsy (access + refresh) per shop Seller App
CREATE TABLE "product"."EtsyOAuthCredential" (
    "id" TEXT NOT NULL,
    "shopId" TEXT NOT NULL,
    "accessToken" TEXT NOT NULL,
    "refreshToken" TEXT NOT NULL,
    "expiresAt" TIMESTAMPTZ(6) NOT NULL,
    "scopes" TEXT NOT NULL DEFAULT '',
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "EtsyOAuthCredential_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "EtsyOAuthCredential_shopId_key" ON "product"."EtsyOAuthCredential"("shopId");
