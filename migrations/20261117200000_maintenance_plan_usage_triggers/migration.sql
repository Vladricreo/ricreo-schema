-- Piani di manutenzione a uso (R-266, 17/11): oltre al calendario, il piano
-- scade dopo N ore di stampa effettive o N kg di materiale (anche solo di
-- certe famiglie, es. abrasivi). Il conteggio riparte a ogni completamento e
-- annullamento (`usageCountFrom`).
--
-- Additiva e idempotente: colonne nullable, nessun dato esistente toccato.

ALTER TABLE "print-farm"."PrinterMaintenancePlan"
  ADD COLUMN IF NOT EXISTS "usagePrintHours" INTEGER,
  ADD COLUMN IF NOT EXISTS "usageMaterialRules" JSONB,
  ADD COLUMN IF NOT EXISTS "usageCountFrom" TIMESTAMPTZ(6);

COMMENT ON COLUMN "print-farm"."PrinterMaintenancePlan"."usagePrintHours"
  IS 'Soglia in ore di stampa effettive dall''inizio del conteggio (NULL = nessuna).';
COMMENT ON COLUMN "print-farm"."PrinterMaintenancePlan"."usageMaterialRules"
  IS 'Soglie a materiale [{kg, families}] dall''inizio del conteggio; families vuoto = tutti i materiali.';
COMMENT ON COLUMN "print-farm"."PrinterMaintenancePlan"."usageCountFrom"
  IS 'Inizio del conteggio ore/kg: riparte a ogni completamento e annullamento. NULL = ultimo completamento o creazione.';
