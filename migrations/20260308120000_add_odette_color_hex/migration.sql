-- Aggiunge il colore dedicato ai tipi di odette.
-- Il valore viene salvato come HEX nel formato #RRGGBB.

ALTER TABLE "inventory"."OdetteType"
ADD COLUMN "colorHex" VARCHAR(7);
