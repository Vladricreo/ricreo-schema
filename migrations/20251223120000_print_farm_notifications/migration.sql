-- Print Farm Notifications (schema: "print-farm")
-- Allinea la struttura a `prisma/schema/print-farm-notifications.prisma`.

-- CreateEnum
CREATE TYPE "print-farm"."PrintFarmNotificationSeverity" AS ENUM ('INFO', 'SUCCESS', 'WARNING', 'ERROR');

-- CreateEnum
CREATE TYPE "print-farm"."PrintFarmNotificationType" AS ENUM ('SYSTEM', 'PRODUCTION', 'PRINTER', 'MAINTENANCE', 'FILES');

-- CreateTable
CREATE TABLE "print-farm"."PrintFarmNotification" (
    "id" UUID NOT NULL,
    "type" "print-farm"."PrintFarmNotificationType" NOT NULL,
    "severity" "print-farm"."PrintFarmNotificationSeverity" NOT NULL DEFAULT 'INFO',
    "title" TEXT NOT NULL,
    "body" TEXT,
    "url" TEXT,
    "createdByUserId" INTEGER,
    "data" JSONB,
    "dedupeKey" TEXT,
    "expiresAt" TIMESTAMPTZ(6),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PrintFarmNotification_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "print-farm"."PrintFarmNotificationRecipient" (
    "id" UUID NOT NULL,
    "notificationId" UUID NOT NULL,
    "userId" INTEGER NOT NULL,
    "isRead" BOOLEAN NOT NULL DEFAULT false,
    "readAt" TIMESTAMPTZ(6),
    "archivedAt" TIMESTAMPTZ(6),
    "deliveredAt" TIMESTAMPTZ(6),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PrintFarmNotificationRecipient_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "PrintFarmNotification_dedupeKey_key" ON "print-farm"."PrintFarmNotification"("dedupeKey");

-- CreateIndex
CREATE INDEX "PrintFarmNotification_type_idx" ON "print-farm"."PrintFarmNotification"("type");

-- CreateIndex
CREATE INDEX "PrintFarmNotification_severity_idx" ON "print-farm"."PrintFarmNotification"("severity");

-- CreateIndex
CREATE INDEX "PrintFarmNotification_createdAt_idx" ON "print-farm"."PrintFarmNotification"("createdAt" DESC);

-- CreateIndex
CREATE INDEX "PrintFarmNotification_createdByUserId_idx" ON "print-farm"."PrintFarmNotification"("createdByUserId");

-- CreateIndex
CREATE INDEX "PrintFarmNotification_expiresAt_idx" ON "print-farm"."PrintFarmNotification"("expiresAt");

-- CreateIndex
CREATE INDEX "PrintFarmNotificationRecipient_userId_isRead_idx" ON "print-farm"."PrintFarmNotificationRecipient"("userId", "isRead");

-- CreateIndex
CREATE INDEX "PrintFarmNotificationRecipient_userId_archivedAt_idx" ON "print-farm"."PrintFarmNotificationRecipient"("userId", "archivedAt");

-- CreateIndex
CREATE INDEX "PrintFarmNotificationRecipient_userId_createdAt_idx" ON "print-farm"."PrintFarmNotificationRecipient"("userId", "createdAt" DESC);

-- CreateIndex
CREATE INDEX "PrintFarmNotificationRecipient_notificationId_idx" ON "print-farm"."PrintFarmNotificationRecipient"("notificationId");

-- CreateIndex
CREATE UNIQUE INDEX "PrintFarmNotificationRecipient_notificationId_userId_key" ON "print-farm"."PrintFarmNotificationRecipient"("notificationId", "userId");

-- AddForeignKey
ALTER TABLE "print-farm"."PrintFarmNotification" ADD CONSTRAINT "PrintFarmNotification_createdByUserId_fkey" FOREIGN KEY ("createdByUserId") REFERENCES "public"."User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."PrintFarmNotificationRecipient" ADD CONSTRAINT "PrintFarmNotificationRecipient_notificationId_fkey" FOREIGN KEY ("notificationId") REFERENCES "print-farm"."PrintFarmNotification"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."PrintFarmNotificationRecipient" ADD CONSTRAINT "PrintFarmNotificationRecipient_userId_fkey" FOREIGN KEY ("userId") REFERENCES "public"."User"("id") ON DELETE CASCADE ON UPDATE CASCADE;


