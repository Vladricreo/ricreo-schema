-- Product Console PWA: push per dispositivo e canale push nelle preferenze inbox.

-- AlterTable
ALTER TABLE "product"."ConsoleNotificationPreference" ADD COLUMN "push" BOOLEAN NOT NULL DEFAULT false;

-- CreateTable
CREATE TABLE "product"."ConsolePushSubscription" (
    "id" TEXT NOT NULL,
    "userId" INTEGER NOT NULL,
    "endpoint" TEXT NOT NULL,
    "p256dh" TEXT NOT NULL,
    "auth" TEXT NOT NULL,
    "userAgent" TEXT,
    "lastSuccessAt" TIMESTAMPTZ(6),
    "failureCount" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ConsolePushSubscription_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "ConsolePushSubscription_endpoint_key" ON "product"."ConsolePushSubscription"("endpoint");

-- CreateIndex
CREATE INDEX "ConsolePushSubscription_userId_idx" ON "product"."ConsolePushSubscription"("userId");

-- AddForeignKey
ALTER TABLE "product"."ConsolePushSubscription" ADD CONSTRAINT "ConsolePushSubscription_userId_fkey" FOREIGN KEY ("userId") REFERENCES "public"."User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
