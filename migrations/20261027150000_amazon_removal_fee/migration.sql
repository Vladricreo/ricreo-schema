-- Rimozioni Amazon: tariffa di rimozione per riga (27/10/2026, tab «Rimozioni Amazon»).
-- Solo colonne nullable: nessun dato esistente cambia; l'import successivo le riempie.
ALTER TABLE "inventory"."AmazonRemovalLine" ADD COLUMN "removalFee" DECIMAL(12,2);
ALTER TABLE "inventory"."AmazonRemovalLine" ADD COLUMN "currency" TEXT;
