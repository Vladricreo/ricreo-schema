/*
  Migrazione: supporto stampe "unplanned" con harvest coerente.

  Obiettivi:
  - Permettere `PrinterAssignment` senza `ProductionJob` (productionJobId nullable).
    Serve per creare assignment anche per stampe manuali / senza prodotto.
  - Salvare la quantità attesa per una singola run in `PrintRun.expectedQuantity`.
    Serve per run con "skip oggetti" (completamento job) e audit.
*/

-- 1) `productionJobId` nullable su PrinterAssignment
ALTER TABLE "print-farm"."PrinterAssignment"
  ALTER COLUMN "productionJobId" DROP NOT NULL;

-- 2) `expectedQuantity` su PrintRun
ALTER TABLE "print-farm"."PrintRun"
  ADD COLUMN IF NOT EXISTS "expectedQuantity" INTEGER;


