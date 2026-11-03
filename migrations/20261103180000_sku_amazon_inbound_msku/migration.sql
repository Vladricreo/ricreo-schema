-- Sku.amazonInboundMsku: seller SKU Amazon da usare nei piani FBA al posto di
-- Sku.code (offerta col codice a barre del produttore su un altro SKU della
-- stessa ASIN, es. TADO-1910-FBA-stickerless). Colonna additiva, null = code.
ALTER TABLE "inventory"."Sku" ADD COLUMN "amazonInboundMsku" TEXT;
