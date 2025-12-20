-- CreateEnum
CREATE TYPE "NotificationSeverity" AS ENUM ('INFO', 'SUCCESS', 'WARNING', 'ERROR');

-- CreateEnum
CREATE TYPE "NotificationType" AS ENUM ('SYSTEM', 'INVENTORY', 'PRODUCTION', 'ASSEMBLY', 'PURCHASING', 'SALES', 'IMPORT', 'AUTH');

-- CreateTable
CREATE TABLE "Notification" (
    "id" UUID NOT NULL,
    "type" "NotificationType" NOT NULL,
    "severity" "NotificationSeverity" NOT NULL DEFAULT 'INFO',
    "title" TEXT NOT NULL,
    "body" TEXT,
    "url" TEXT,
    "createdByUserId" INTEGER,
    "data" JSONB,
    "dedupeKey" TEXT,
    "expiresAt" TIMESTAMPTZ(6),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Notification_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "NotificationRecipient" (
    "id" UUID NOT NULL,
    "notificationId" UUID NOT NULL,
    "userId" INTEGER NOT NULL,
    "isRead" BOOLEAN NOT NULL DEFAULT false,
    "readAt" TIMESTAMPTZ(6),
    "archivedAt" TIMESTAMPTZ(6),
    "deliveredAt" TIMESTAMPTZ(6),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "NotificationRecipient_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "Notification_dedupeKey_key" ON "Notification"("dedupeKey");

-- CreateIndex
CREATE INDEX "Notification_type_idx" ON "Notification"("type");

-- CreateIndex
CREATE INDEX "Notification_severity_idx" ON "Notification"("severity");

-- CreateIndex
CREATE INDEX "Notification_createdAt_idx" ON "Notification"("createdAt" DESC);

-- CreateIndex
CREATE INDEX "Notification_createdByUserId_idx" ON "Notification"("createdByUserId");

-- CreateIndex
CREATE INDEX "Notification_expiresAt_idx" ON "Notification"("expiresAt");

-- CreateIndex
CREATE INDEX "NotificationRecipient_userId_isRead_idx" ON "NotificationRecipient"("userId", "isRead");

-- CreateIndex
CREATE INDEX "NotificationRecipient_userId_archivedAt_idx" ON "NotificationRecipient"("userId", "archivedAt");

-- CreateIndex
CREATE INDEX "NotificationRecipient_userId_createdAt_idx" ON "NotificationRecipient"("userId", "createdAt" DESC);

-- CreateIndex
CREATE INDEX "NotificationRecipient_notificationId_idx" ON "NotificationRecipient"("notificationId");

-- CreateIndex
CREATE UNIQUE INDEX "NotificationRecipient_notificationId_userId_key" ON "NotificationRecipient"("notificationId", "userId");

-- AddForeignKey
ALTER TABLE "Notification" ADD CONSTRAINT "Notification_createdByUserId_fkey" FOREIGN KEY ("createdByUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "NotificationRecipient" ADD CONSTRAINT "NotificationRecipient_notificationId_fkey" FOREIGN KEY ("notificationId") REFERENCES "Notification"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "NotificationRecipient" ADD CONSTRAINT "NotificationRecipient_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
