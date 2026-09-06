-- Indice per le finestre equal-time delle coorti di lancio (ASIN × data ordine).
-- Solo schema product.

CREATE INDEX IF NOT EXISTS "StoreOrderLine_channel_asin_date"
    ON product."StoreOrderLine" (channel, asin, "purchaseDate");
