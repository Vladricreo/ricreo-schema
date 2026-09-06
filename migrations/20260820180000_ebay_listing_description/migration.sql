-- Template JSON della descrizione eBay (badge, bullet e testo IT/EN).

CREATE TABLE IF NOT EXISTS "product"."EbayListingDescription" (
    "id" TEXT NOT NULL,
    "listingId" TEXT NOT NULL,
    "sku" TEXT,
    "content" JSONB NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "EbayListingDescription_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "EbayListingDescription_listing"
    ON "product"."EbayListingDescription" ("listingId");

CREATE INDEX IF NOT EXISTS "EbayListingDescription_sku"
    ON "product"."EbayListingDescription" ("sku");
