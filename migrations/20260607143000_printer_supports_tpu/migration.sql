-- Compatibilità TPU/TPE per-stampante.
-- Alcune macchine hanno il modulo TPU installato (compatibilità individuale, non per modello):
-- quando false lo scheduler non assegna a questa stampante job con materiale TPU/TPE.
--
-- Additiva e idempotente: solo ADD COLUMN con IF NOT EXISTS, default false (nessun consumer rotto).

ALTER TABLE "print-farm"."Printer"
  ADD COLUMN IF NOT EXISTS "supportsTpu" BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN "print-farm"."Printer"."supportsTpu"
  IS 'True se la stampante ha il modulo TPU/TPE installato (compatibilità per-stampante). False: lo scheduler esclude i job TPU/TPE.';
