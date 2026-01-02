-- Rendiamo `skuId` nullable per permettere righe con SKU sconosciuto.
-- Questo consente di importare tutti gli ordini senza perdere righe non "linkabili".

ALTER TABLE "inventory"."ShipmentLine"
ALTER COLUMN "skuId" DROP NOT NULL;

