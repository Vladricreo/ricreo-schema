-- Stato account Amazon e dettaglio issue listing.
-- StoreListingIssue: categorie, enforcement e attributi per distinguere
-- conformità normativa (GPSR, documenti richiesti) e listing soppressi.
-- AmazonAccountHealth: ultima lettura di GET_V2_SELLER_PERFORMANCE_REPORT
-- per marketplace (AHR, violazioni, metriche). Letti da /dashboard/listings.

-- AlterTable
ALTER TABLE "product"."StoreListingIssue"
  ADD COLUMN "categories" TEXT[] DEFAULT ARRAY[]::TEXT[],
  ADD COLUMN "enforcementActions" TEXT[] DEFAULT ARRAY[]::TEXT[],
  ADD COLUMN "attributeNames" TEXT[] DEFAULT ARRAY[]::TEXT[];

-- CreateTable
CREATE TABLE "product"."AmazonAccountHealth" (
    "marketplaceId" TEXT NOT NULL,
    "countryCode" TEXT NOT NULL,
    "accountStatus" TEXT,
    "ahrScore" DOUBLE PRECISION,
    "ahrStatus" TEXT,
    "snapshot" JSONB NOT NULL,
    "raw" JSONB NOT NULL,
    "reportId" TEXT,
    "fetchedAt" TIMESTAMPTZ(6) NOT NULL,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "AmazonAccountHealth_pkey" PRIMARY KEY ("marketplaceId")
);
