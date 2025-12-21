-- Riduzione scala decimali (prezzi/pesi) a 2 cifre decimali.
-- Nota: per dati già presenti, usiamo ROUND(..., 2) per evitare errori e mantenere coerenza.

-- Item
ALTER TABLE "inventory"."Item"
ALTER COLUMN "price" TYPE DECIMAL(12,2)
USING ROUND("price"::numeric, 2);

ALTER TABLE "inventory"."Item"
ALTER COLUMN "weight" TYPE DECIMAL(12,2)
USING ROUND("weight"::numeric, 2);

-- Product (campi prezzo/costo)
ALTER TABLE "inventory"."Product"
ALTER COLUMN "cost" TYPE DECIMAL(12,2)
USING ROUND("cost"::numeric, 2);

ALTER TABLE "inventory"."Product"
ALTER COLUMN "estimatedPrice" TYPE DECIMAL(12,2)
USING ROUND("estimatedPrice"::numeric, 2);

ALTER TABLE "inventory"."Product"
ALTER COLUMN "sellingPrice" TYPE DECIMAL(12,2)
USING ROUND("sellingPrice"::numeric, 2);

ALTER TABLE "inventory"."Product"
ALTER COLUMN "laborCost" TYPE DECIMAL(12,2)
USING ROUND("laborCost"::numeric, 2);

-- ProductPart (prezzo)
ALTER TABLE "inventory"."ProductPart"
ALTER COLUMN "price" TYPE DECIMAL(12,2)
USING ROUND("price"::numeric, 2);

-- ProductPartMaterial (grammi usati)
ALTER TABLE "inventory"."ProductPartMaterial"
ALTER COLUMN "usedWeight" TYPE DECIMAL(12,2)
USING ROUND("usedWeight"::numeric, 2);

-- Dimensions
ALTER TABLE "inventory"."Dimensions"
ALTER COLUMN "width" TYPE DECIMAL(12,2)
USING ROUND("width"::numeric, 2);

ALTER TABLE "inventory"."Dimensions"
ALTER COLUMN "height" TYPE DECIMAL(12,2)
USING ROUND("height"::numeric, 2);

ALTER TABLE "inventory"."Dimensions"
ALTER COLUMN "depth" TYPE DECIMAL(12,2)
USING ROUND("depth"::numeric, 2);

-- StandardWeight
ALTER TABLE "inventory"."StandardWeight"
ALTER COLUMN "weight" TYPE DECIMAL(12,2)
USING ROUND("weight"::numeric, 2);


