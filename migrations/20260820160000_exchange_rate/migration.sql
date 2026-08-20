-- Tassi di cambio verso EUR (Frankfurter). Solo schema product.

CREATE TABLE IF NOT EXISTS "product"."ExchangeRate" (
    "id" TEXT NOT NULL,
    "currency" TEXT NOT NULL,
    "base" TEXT NOT NULL DEFAULT 'EUR',
    "rate" DECIMAL(18,8) NOT NULL,
    "rateDate" DATE NOT NULL,
    "source" TEXT NOT NULL DEFAULT 'frankfurter',
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ExchangeRate_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "ExchangeRate_currency"
    ON "product"."ExchangeRate" ("currency");
CREATE INDEX IF NOT EXISTS "ExchangeRate_rateDate"
    ON "product"."ExchangeRate" ("rateDate");
