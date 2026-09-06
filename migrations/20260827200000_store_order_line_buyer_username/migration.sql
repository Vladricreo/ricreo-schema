-- Username acquirente sulla riga ordine: collega le conversazioni eBay
-- (che espongono solo inserzione + username) all'ordine e alla spedizione.
-- Solo schema product.

ALTER TABLE "product"."StoreOrderLine"
ADD COLUMN IF NOT EXISTS "buyerUsername" TEXT;

CREATE INDEX IF NOT EXISTS "StoreOrderLine_channel_buyerUsername_idx"
ON "product"."StoreOrderLine"("channel", "buyerUsername");
