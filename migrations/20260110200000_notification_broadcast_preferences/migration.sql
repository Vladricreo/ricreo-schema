-- ============================================================================
-- Migration: Add broadcast flag and notification preferences
-- ============================================================================

-- Add isBroadcast column to PrintFarmNotification
ALTER TABLE "print-farm"."PrintFarmNotification"
ADD COLUMN "isBroadcast" BOOLEAN NOT NULL DEFAULT false;

-- Create index for isBroadcast
CREATE INDEX "PrintFarmNotification_isBroadcast_idx"
ON "print-farm"."PrintFarmNotification"("isBroadcast");

-- Create PrintFarmNotificationPreference table
CREATE TABLE "print-farm"."PrintFarmNotificationPreference" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "userId" INTEGER NOT NULL,
    "type" "print-farm"."PrintFarmNotificationType" NOT NULL,
    "enabled" BOOLEAN NOT NULL DEFAULT true,
    "minSeverity" "print-farm"."PrintFarmNotificationSeverity" NOT NULL DEFAULT 'INFO',
    "inApp" BOOLEAN NOT NULL DEFAULT true,
    "email" BOOLEAN NOT NULL DEFAULT false,
    "push" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT now(),
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT now(),

    CONSTRAINT "PrintFarmNotificationPreference_pkey" PRIMARY KEY ("id")
);

-- Create unique constraint on (userId, type)
CREATE UNIQUE INDEX "PrintFarmNotificationPreference_userId_type_key"
ON "print-farm"."PrintFarmNotificationPreference"("userId", "type");

-- Create index on userId
CREATE INDEX "PrintFarmNotificationPreference_userId_idx"
ON "print-farm"."PrintFarmNotificationPreference"("userId");

-- Add foreign key constraint to User table
ALTER TABLE "print-farm"."PrintFarmNotificationPreference"
ADD CONSTRAINT "PrintFarmNotificationPreference_userId_fkey"
FOREIGN KEY ("userId") REFERENCES "public"."User"("id")
ON DELETE CASCADE ON UPDATE CASCADE;
