-- Motivo reso: codice selezionabile (reason) + testo descrittivo (customer-comments).
ALTER TABLE "product"."StoreReturnLine"
  ADD COLUMN "reasonDescription" TEXT;
