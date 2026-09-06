-- Indirizzo di spedizione su StoreOrderLine (PII). Etsy lo manda sul receipt;
-- eBay su Fulfillment/Trading; Amazon all-orders di solito solo città/CAP/stato.

ALTER TABLE "product"."StoreOrderLine"
ADD COLUMN "shipRecipientName" TEXT,
ADD COLUMN "shipAddressLine1" TEXT,
ADD COLUMN "shipAddressLine2" TEXT,
ADD COLUMN "shipCity" TEXT,
ADD COLUMN "shipState" TEXT,
ADD COLUMN "shipPostalCode" TEXT,
ADD COLUMN "shipFormattedAddress" TEXT,
ADD COLUMN "shipPhone" TEXT,
ADD COLUMN "buyerEmail" TEXT;
