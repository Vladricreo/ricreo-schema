-- Priorità operativa distinta dalla severity.
-- BASE=Base, MEDIUM=Media, HIGH=Alta, CRITICAL=Critica.

DO $$ BEGIN
  CREATE TYPE "NotificationPriority" AS ENUM ('BASE', 'MEDIUM', 'HIGH', 'CRITICAL');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE "Notification"
  ADD COLUMN IF NOT EXISTS "priority" "NotificationPriority" NOT NULL DEFAULT 'BASE';

UPDATE "Notification"
SET "priority" = CASE "severity"
  WHEN 'ERROR' THEN 'CRITICAL'::"NotificationPriority"
  WHEN 'WARNING' THEN 'HIGH'::"NotificationPriority"
  WHEN 'SUCCESS' THEN 'MEDIUM'::"NotificationPriority"
  ELSE 'BASE'::"NotificationPriority"
END;

CREATE INDEX IF NOT EXISTS "Notification_priority_idx" ON "Notification"("priority");

-- Archivia il rumore "ordine di produzione/assemblaggio creato/aggiornato".
UPDATE "NotificationRecipient" AS nr
SET
  "archivedAt" = COALESCE(nr."archivedAt", NOW()),
  "isRead" = true,
  "readAt" = COALESCE(nr."readAt", NOW()),
  "updatedAt" = NOW()
FROM "Notification" AS n
WHERE nr."notificationId" = n.id
  AND nr."archivedAt" IS NULL
  AND (
    n."dedupeKey" LIKE 'production:product-order-created:%'
    OR n."dedupeKey" LIKE 'assembly:order-created:%'
    OR n."dedupeKey" LIKE 'assembly:order-aggiornato:%'
    OR n.title LIKE 'Ordine di produzione creato%'
    OR n.title LIKE 'Ordine di assemblaggio creato%'
    OR n.title LIKE 'Ordine di assemblaggio aggiornato%'
  );
