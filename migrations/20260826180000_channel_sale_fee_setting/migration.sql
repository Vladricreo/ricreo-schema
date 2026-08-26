-- Commissioni eBay / Etsy / Temu modificabili dalla pagina Profitto.
-- Solo schema product.

CREATE TABLE IF NOT EXISTS "product"."ChannelSaleFeeSetting" (
    "id" TEXT NOT NULL,
    "ebayPercent" DECIMAL(5,2) NOT NULL DEFAULT 12.8,
    "ebayFixedEur" DECIMAL(8,2) NOT NULL DEFAULT 0.35,
    "etsyPercent" DECIMAL(5,2) NOT NULL DEFAULT 10.5,
    "etsyFixedEur" DECIMAL(8,2) NOT NULL DEFAULT 0.30,
    "temuPercent" DECIMAL(5,2) NOT NULL DEFAULT 15,
    "temuFixedEur" DECIMAL(8,2) NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ChannelSaleFeeSetting_pkey" PRIMARY KEY ("id")
);

INSERT INTO "product"."ChannelSaleFeeSetting" (
    "id",
    "ebayPercent",
    "ebayFixedEur",
    "etsyPercent",
    "etsyFixedEur",
    "temuPercent",
    "temuFixedEur",
    "createdAt",
    "updatedAt"
)
VALUES ('default', 12.8, 0.35, 10.5, 0.30, 15, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
ON CONFLICT ("id") DO NOTHING;
