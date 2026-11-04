-- R-182 (04/11): slot AMS fuori uso, per stampante, come codici globali
-- (`encodeAmsGlobalSlot`: unità × 4 + slot, AMS-HT = 128). Default vuoto:
-- nessun effetto finché l'operatore non segna uno slot in Impostazioni → Stampanti.
ALTER TABLE "print-farm"."Printer"
  ADD COLUMN "outOfServiceAmsSlots" INTEGER[] DEFAULT ARRAY[]::INTEGER[];
