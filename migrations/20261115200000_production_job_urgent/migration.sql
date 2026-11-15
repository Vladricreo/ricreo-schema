-- Urgenza manuale di un job (15/11): toggle «Urgente» nella pagina Job.
-- Finché il job è aperto lo scheduler (legacy e Gantt) lo tratta un livello
-- sopra la critica (P5). `priority` resta quella dell'ordine, che il cron
-- update-production-status riscrive; questa colonna non la tocca nessun cron.
-- Colonna nullable, nessun dato esistente toccato.
-- Va applicata PRIMA del deploy del client: Prisma legge tutte le colonne
-- scalari del job e senza la colonna le query sui job fallirebbero.

-- AlterTable
ALTER TABLE "print-farm"."ProductionJob" ADD COLUMN "urgentAt" TIMESTAMPTZ(6);
