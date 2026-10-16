-- Notifiche push Print Farm (PWA): sottoscrizioni Web Push per dispositivo e
-- preferenza `push` attiva di default per tipo di notifica.
-- Solo le notifiche Print Farm (`PrintFarmNotification`) vengono inviate in push.

-- CreateTable
CREATE TABLE IF NOT EXISTS "print-farm"."PrintFarmPushSubscription" (
    "id" UUID NOT NULL,
    "userId" INTEGER NOT NULL,
    "endpoint" TEXT NOT NULL,
    "p256dh" TEXT NOT NULL,
    "auth" TEXT NOT NULL,
    "userAgent" TEXT,
    "lastSuccessAt" TIMESTAMPTZ(6),
    "failureCount" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PrintFarmPushSubscription_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX IF NOT EXISTS "PrintFarmPushSubscription_endpoint_key" ON "print-farm"."PrintFarmPushSubscription"("endpoint");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "PrintFarmPushSubscription_userId_idx" ON "print-farm"."PrintFarmPushSubscription"("userId");

-- AddForeignKey
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'PrintFarmPushSubscription_userId_fkey'
  ) THEN
    ALTER TABLE "print-farm"."PrintFarmPushSubscription" ADD CONSTRAINT "PrintFarmPushSubscription_userId_fkey" FOREIGN KEY ("userId") REFERENCES "public"."User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;

-- AlterTable: push attivo di default. Il canale push non era mai stato esposto in UI,
-- quindi i `false` esistenti sono solo il vecchio default, non una scelta dell'utente.
ALTER TABLE "print-farm"."PrintFarmNotificationPreference" ALTER COLUMN "push" SET DEFAULT true;
UPDATE "print-farm"."PrintFarmNotificationPreference" SET "push" = true WHERE "push" = false;
