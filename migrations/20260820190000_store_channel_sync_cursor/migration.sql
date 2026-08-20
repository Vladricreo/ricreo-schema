-- Cursore di sync incrementale per ordini/rimborsi eBay, Etsy e Temu.

CREATE TABLE IF NOT EXISTS "product"."StoreChannelSyncCursor" (
    "id" TEXT NOT NULL,
    "channel" "product"."StoreChannel" NOT NULL,
    "storeKey" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "watermark" TIMESTAMPTZ(6),
    "offset" INTEGER NOT NULL DEFAULT 0,
    "pagesFetched" INTEGER NOT NULL DEFAULT 0,
    "itemsUpserted" INTEGER NOT NULL DEFAULT 0,
    "rangeFrom" TIMESTAMPTZ(6),
    "rangeTo" TIMESTAMPTZ(6),
    "errorMessage" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "StoreChannelSyncCursor_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "StoreChannelSyncCursor_key"
    ON "product"."StoreChannelSyncCursor" ("channel", "storeKey", "kind");

CREATE INDEX IF NOT EXISTS "StoreChannelSyncCursor_channel_kind"
    ON "product"."StoreChannelSyncCursor" ("channel", "kind");
