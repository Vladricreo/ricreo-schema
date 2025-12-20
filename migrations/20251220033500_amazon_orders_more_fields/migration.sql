-- Estende AmazonOrder/AmazonOrderItem con campi utili per:
-- - quantity e conteggi ordine
-- - prezzi/tasse/sconti (anche VAT-exclusive)
-- - alcune info di spedizione (attenzione PII: CAP mascherato lato app)

ALTER TABLE "inventory"."AmazonOrder"
  ADD COLUMN "buyerTaxRegistrationCountry" TEXT,
  ADD COLUMN "buyerTaxRegistrationType" TEXT,
  ADD COLUMN "iossNumber" TEXT,
  ADD COLUMN "isAmazonInvoiced" BOOLEAN,
  ADD COLUMN "isIba" BOOLEAN,
  ADD COLUMN "merchantOrderId" TEXT,
  ADD COLUMN "numberOfItems" INTEGER,
  ADD COLUMN "orderInvoiceType" TEXT,
  ADD COLUMN "priceDesignation" TEXT,
  ADD COLUMN "promotionIds" TEXT,
  ADD COLUMN "shipCity" TEXT,
  ADD COLUMN "shipCountry" TEXT,
  ADD COLUMN "shipPostalCode" TEXT,
  ADD COLUMN "shipServiceLevel" TEXT,
  ADD COLUMN "shipState" TEXT;

ALTER TABLE "inventory"."AmazonOrderItem"
  ADD COLUMN "giftWrapPrice" DECIMAL(12,4),
  ADD COLUMN "giftWrapTax" DECIMAL(12,4),
  ADD COLUMN "itemStatus" TEXT,
  ADD COLUMN "productName" TEXT,
  ADD COLUMN "vatExclusiveGiftwrapPrice" DECIMAL(12,4),
  ADD COLUMN "vatExclusiveItemPrice" DECIMAL(12,4),
  ADD COLUMN "vatExclusiveShippingPrice" DECIMAL(12,4);

