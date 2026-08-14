-- Indici per la lista analytics: aggregazione per SKU e DISTINCT ON sulla data.
-- Non tocca inventory.

CREATE INDEX "StoreSalesDaily_channel_sku_date_idx"
    ON "product"."StoreSalesDaily"("channel", "sku", "date");

CREATE INDEX "StoreOrderLine_channel_sku_purchaseDate_idx"
    ON "product"."StoreOrderLine"("channel", "sku", "purchaseDate");
