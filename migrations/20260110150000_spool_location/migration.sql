-- Aggiunge locationId a FilamentSpool per tracciare la posizione in magazzino delle bobine parziali

-- Aggiungi colonna locationId
ALTER TABLE "print-farm"."FilamentSpool" ADD COLUMN "locationId" UUID;

-- Crea indice per query su location
CREATE INDEX "FilamentSpool_locationId_idx" ON "print-farm"."FilamentSpool"("locationId");

-- Aggiungi foreign key verso WarehouseLocation (schema inventory)
ALTER TABLE "print-farm"."FilamentSpool" 
ADD CONSTRAINT "FilamentSpool_locationId_fkey" 
FOREIGN KEY ("locationId") 
REFERENCES "inventory"."WarehouseLocation"("id") 
ON DELETE SET NULL ON UPDATE CASCADE;
