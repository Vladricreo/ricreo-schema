-- Anagrafica fornitori: logo, fiscale, consegna, pagamenti e payload API.
ALTER TABLE "inventory"."Supplier"
  ADD COLUMN "logoUrl" TEXT,
  ADD COLUMN "vatNumber" TEXT,
  ADD COLUMN "taxCode" TEXT,
  ADD COLUMN "pec" TEXT,
  ADD COLUMN "sdiCode" TEXT,
  ADD COLUMN "phone" TEXT,
  ADD COLUMN "contactName" TEXT,
  ADD COLUMN "contactRole" TEXT,
  ADD COLUMN "addressLine" TEXT,
  ADD COLUMN "city" TEXT,
  ADD COLUMN "province" TEXT,
  ADD COLUMN "postalCode" TEXT,
  ADD COLUMN "country" TEXT DEFAULT 'IT',
  ADD COLUMN "notes" TEXT,
  ADD COLUMN "paymentTermsDays" INTEGER,
  ADD COLUMN "paymentMethod" TEXT,
  ADD COLUMN "currency" TEXT DEFAULT 'EUR',
  ADD COLUMN "minOrderAmount" DECIMAL(12,2),
  ADD COLUMN "customerCode" TEXT,
  ADD COLUMN "leadTimeMin" INTEGER,
  ADD COLUMN "leadTimeMax" INTEGER,
  ADD COLUMN "preferredCarrier" TEXT,
  ADD COLUMN "incoterms" TEXT,
  ADD COLUMN "isActive" BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN "accentColor" TEXT,
  ADD COLUMN "apiPayload" JSONB;

CREATE UNIQUE INDEX "Supplier_vatNumber_key" ON "inventory"."Supplier"("vatNumber");
CREATE INDEX "Supplier_isActive_idx" ON "inventory"."Supplier"("isActive");
CREATE INDEX "Supplier_country_idx" ON "inventory"."Supplier"("country");
