-- Shopify come nuovo canale di vendita (store Ricreo su Shopify).
-- Solo estensione degli enum: nessuna riga esistente toccata.
-- `Shipment.salesChannel` è scritto anche dalla sync Sendcloud nell'altra app:
-- lì va mappata l'integrazione Shopify su SHOPIFY.

-- AlterEnum
ALTER TYPE "product"."StoreChannel" ADD VALUE IF NOT EXISTS 'SHOPIFY';

-- AlterEnum
ALTER TYPE "inventory"."ShipmentSalesChannel" ADD VALUE IF NOT EXISTS 'SHOPIFY';
