-- Alias paese libero → ISO-2 (IVA destinazione Etsy)
CREATE TABLE "product"."StoreCountryAlias" (
    "id" TEXT NOT NULL,
    "rawName" TEXT NOT NULL,
    "countryCode" CHAR(2) NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "StoreCountryAlias_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "StoreCountryAlias_rawName_key" ON "product"."StoreCountryAlias"("rawName");
CREATE INDEX "StoreCountryAlias_countryCode_idx" ON "product"."StoreCountryAlias"("countryCode");
