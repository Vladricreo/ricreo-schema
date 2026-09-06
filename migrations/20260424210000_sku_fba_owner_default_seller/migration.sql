-- Cambia il default dei campi FBA owner sullo Sku da NONE a SELLER.
-- I dati esistenti restano invariati (gli SKU attualmente a NONE rimangono a NONE,
-- perche' sono stati impostati esplicitamente per usare il barcode del produttore).
-- Solo i nuovi SKU creati senza configurazione esplicita useranno SELLER come default
-- (richiedono FNSKU finche' il listing non e' configurato in modalita' Manufacturer Barcode).

ALTER TABLE "inventory"."Sku"
  ALTER COLUMN "fbaLabelOwner" SET DEFAULT 'SELLER',
  ALTER COLUMN "fbaPrepOwner"  SET DEFAULT 'SELLER';
