-- Riduzione scala decimali a 2 cifre dove ha senso (soldi + pesi/dimensioni principali).
-- Nota: per dati già presenti, usiamo ROUND(..., 2) per evitare errori e mantenere coerenza.

-- =========================
-- Schema: inventory
-- =========================

-- Product (metriche vendite)
ALTER TABLE "inventory"."Product"
ALTER COLUMN "averageDailySales" TYPE DECIMAL(12,2)
USING ROUND("averageDailySales"::numeric, 2);

-- AmazonProduct (soldi + peso)
ALTER TABLE "inventory"."AmazonProduct"
ALTER COLUMN "price" TYPE DECIMAL(12,2)
USING ROUND("price"::numeric, 2);

ALTER TABLE "inventory"."AmazonProduct"
ALTER COLUMN "salesVelocity" TYPE DECIMAL(12,2)
USING ROUND("salesVelocity"::numeric, 2);

ALTER TABLE "inventory"."AmazonProduct"
ALTER COLUMN "weight" TYPE DECIMAL(12,2)
USING ROUND("weight"::numeric, 2);

-- AmazonOrderItem (soldi)
ALTER TABLE "inventory"."AmazonOrderItem"
ALTER COLUMN "itemPrice" TYPE DECIMAL(12,2)
USING ROUND("itemPrice"::numeric, 2);

ALTER TABLE "inventory"."AmazonOrderItem"
ALTER COLUMN "itemTax" TYPE DECIMAL(12,2)
USING ROUND("itemTax"::numeric, 2);

ALTER TABLE "inventory"."AmazonOrderItem"
ALTER COLUMN "shippingPrice" TYPE DECIMAL(12,2)
USING ROUND("shippingPrice"::numeric, 2);

ALTER TABLE "inventory"."AmazonOrderItem"
ALTER COLUMN "shippingTax" TYPE DECIMAL(12,2)
USING ROUND("shippingTax"::numeric, 2);

ALTER TABLE "inventory"."AmazonOrderItem"
ALTER COLUMN "giftWrapPrice" TYPE DECIMAL(12,2)
USING ROUND("giftWrapPrice"::numeric, 2);

ALTER TABLE "inventory"."AmazonOrderItem"
ALTER COLUMN "giftWrapTax" TYPE DECIMAL(12,2)
USING ROUND("giftWrapTax"::numeric, 2);

ALTER TABLE "inventory"."AmazonOrderItem"
ALTER COLUMN "itemPromotionDiscount" TYPE DECIMAL(12,2)
USING ROUND("itemPromotionDiscount"::numeric, 2);

ALTER TABLE "inventory"."AmazonOrderItem"
ALTER COLUMN "shipPromotionDiscount" TYPE DECIMAL(12,2)
USING ROUND("shipPromotionDiscount"::numeric, 2);

ALTER TABLE "inventory"."AmazonOrderItem"
ALTER COLUMN "vatExclusiveItemPrice" TYPE DECIMAL(12,2)
USING ROUND("vatExclusiveItemPrice"::numeric, 2);

ALTER TABLE "inventory"."AmazonOrderItem"
ALTER COLUMN "vatExclusiveShippingPrice" TYPE DECIMAL(12,2)
USING ROUND("vatExclusiveShippingPrice"::numeric, 2);

ALTER TABLE "inventory"."AmazonOrderItem"
ALTER COLUMN "vatExclusiveGiftwrapPrice" TYPE DECIMAL(12,2)
USING ROUND("vatExclusiveGiftwrapPrice"::numeric, 2);

-- PurchaseOrder (soldi)
ALTER TABLE "inventory"."PurchaseOrder"
ALTER COLUMN "shippingCost" TYPE DECIMAL(12,2)
USING ROUND("shippingCost"::numeric, 2);

ALTER TABLE "inventory"."PurchaseOrder"
ALTER COLUMN "customsDuty" TYPE DECIMAL(12,2)
USING ROUND("customsDuty"::numeric, 2);

-- PurchaseOrderLine (soldi)
ALTER TABLE "inventory"."PurchaseOrderLine"
ALTER COLUMN "pricePaid" TYPE DECIMAL(12,2)
USING ROUND("pricePaid"::numeric, 2);

-- ProductOrder (costo)
ALTER TABLE "inventory"."ProductOrder"
ALTER COLUMN "cost" TYPE DECIMAL(12,2)
USING ROUND("cost"::numeric, 2);

-- =========================
-- Schema: print-farm
-- =========================

-- ProjectThreeMFFile (dimensione/peso)
ALTER TABLE "print-farm"."ProjectThreeMFFile"
ALTER COLUMN "zHeight" TYPE DECIMAL(12,2)
USING ROUND("zHeight"::numeric, 2);

ALTER TABLE "print-farm"."ProjectThreeMFFile"
ALTER COLUMN "totalFilamentWeight" TYPE DECIMAL(12,2)
USING ROUND("totalFilamentWeight"::numeric, 2);

-- ProjectFileMaterial (peso)
ALTER TABLE "print-farm"."ProjectFileMaterial"
ALTER COLUMN "usedWeight" TYPE DECIMAL(12,2)
USING ROUND("usedWeight"::numeric, 2);

-- ProjectPart (peso)
ALTER TABLE "print-farm"."ProjectPart"
ALTER COLUMN "weight" TYPE DECIMAL(12,2)
USING ROUND("weight"::numeric, 2);

-- PrintRun (costo energia)
ALTER TABLE "print-farm"."PrintRun"
ALTER COLUMN "energyCostSnapshot" TYPE DECIMAL(12,2)
USING ROUND("energyCostSnapshot"::numeric, 2);

-- FilamentSpool (peso bobine)
ALTER TABLE "print-farm"."FilamentSpool"
ALTER COLUMN "initialWeight" TYPE DECIMAL(10,2)
USING ROUND("initialWeight"::numeric, 2);

ALTER TABLE "print-farm"."FilamentSpool"
ALTER COLUMN "remainingWeight" TYPE DECIMAL(10,2)
USING ROUND("remainingWeight"::numeric, 2);


