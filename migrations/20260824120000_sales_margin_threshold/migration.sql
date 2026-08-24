-- Soglie modificabili per i colori del margine in analytics vendite.
-- Solo schema product.

CREATE TABLE IF NOT EXISTS "product"."SalesMarginThreshold" (
    "id" TEXT NOT NULL,
    "lowMaxPercent" DECIMAL(5,2) NOT NULL DEFAULT 30,
    "goodMinPercent" DECIMAL(5,2) NOT NULL DEFAULT 45,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SalesMarginThreshold_pkey" PRIMARY KEY ("id")
);

INSERT INTO "product"."SalesMarginThreshold" (
    "id",
    "lowMaxPercent",
    "goodMinPercent",
    "createdAt",
    "updatedAt"
)
VALUES ('default', 30, 45, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
ON CONFLICT ("id") DO NOTHING;
