-- Totale vita vendite per offerta eBay (Trading GetItem QuantitySold).
ALTER TABLE "product"."CompetitorListingOffer"
    ADD COLUMN "quantitySold" INTEGER;
