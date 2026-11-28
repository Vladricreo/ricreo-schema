-- Bozze di scarico: quando l'operatore (tablet o voce) ha scelto la destinazione dell'odette.
--
-- Il ricalcolo delle posizioni "tenute dalle bozze" (resolveStaleDraftTargets) guardava solo
-- la creazione della bozza: se un'altra odette era arrivata nella posizione dopo la creazione,
-- o la posizione impilava, la scelta dell'operatore veniva sostituita a ogni giro della lista,
-- anche quando l'aveva fatta apposta dopo aver visto quell'odette (utente 28/11).
--
-- Solo aggiunta di una colonna nullable, ripetibile.

ALTER TABLE "print-farm"."HarvestDraft"
  ADD COLUMN IF NOT EXISTS "targetLocationSetAt" TIMESTAMPTZ(6);
