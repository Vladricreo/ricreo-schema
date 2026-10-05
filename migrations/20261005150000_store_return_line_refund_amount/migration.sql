-- ============================================================================
-- Importo rimborsato per riga reso (StoreReturnLine.refundAmount).
--
-- Serve ai corrispettivi Etsy da product: StoreReturnLine aveva solo la
-- quantità, non l'importo. Etsy manda il rimborso a livello receipt; l'import
-- lo ripartisce sulle righe (allocateRefundToLines) e salva la quota qui.
-- IF NOT EXISTS: la colonna può essere già stata creata a mano su ricreo-db.
-- ============================================================================

ALTER TABLE "product"."StoreReturnLine"
  ADD COLUMN IF NOT EXISTS "refundAmount" DECIMAL(12,2);
