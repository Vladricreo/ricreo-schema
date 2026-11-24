-- Cronologia di Product Console (24/11/2026): una riga per ogni azione fatta nell'app
-- (modifiche ai listing, prezzi, scorte, pubblicazioni, eliminazioni…), con chi l'ha
-- fatta, quando, su quale store e con quale esito.
--
-- Additiva: un enum e una tabella nuovi nello schema `product`. Non tocca tabelle esistenti.

DO $$
BEGIN
  CREATE TYPE "product"."ConsoleActivityActorKind" AS ENUM ('USER', 'OPERATOR', 'SYSTEM');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END
$$;

CREATE TABLE IF NOT EXISTS "product"."ConsoleActivityEvent" (
  "id" TEXT NOT NULL,
  "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "actorKind" "product"."ConsoleActivityActorKind" NOT NULL DEFAULT 'SYSTEM',
  "actorUserId" INTEGER,
  "actorName" TEXT,
  "area" TEXT NOT NULL,
  "action" TEXT NOT NULL,
  "title" TEXT NOT NULL,
  "channel" "product"."StoreChannel",
  "storeKey" TEXT,
  "sku" TEXT,
  "entityId" TEXT,
  "entityLabel" TEXT,
  "changes" JSONB,
  "data" JSONB,
  "ok" BOOLEAN NOT NULL DEFAULT true,
  "error" TEXT,
  "url" TEXT,

  CONSTRAINT "ConsoleActivityEvent_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "ConsoleActivityEvent_createdAt"
  ON "product"."ConsoleActivityEvent" ("createdAt" DESC);
CREATE INDEX IF NOT EXISTS "ConsoleActivityEvent_sku"
  ON "product"."ConsoleActivityEvent" ("sku", "createdAt" DESC);
CREATE INDEX IF NOT EXISTS "ConsoleActivityEvent_actor"
  ON "product"."ConsoleActivityEvent" ("actorUserId", "createdAt" DESC);
CREATE INDEX IF NOT EXISTS "ConsoleActivityEvent_action"
  ON "product"."ConsoleActivityEvent" ("area", "action", "createdAt" DESC);
CREATE INDEX IF NOT EXISTS "ConsoleActivityEvent_store"
  ON "product"."ConsoleActivityEvent" ("channel", "storeKey", "createdAt" DESC);
