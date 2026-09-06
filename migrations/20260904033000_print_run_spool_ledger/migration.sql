-- ============================================================================
-- Ledger consumo run↔spool — Ondata 7, tracciabilità (W-LEDGER).
-- (audit 2026-09-03: TRACCIABILITA.md gap #1 — "la tabella chiave mancante:
--  per run, per bobina, grammi"; chiude il gap #1 e prepara il #2)
--
-- Cosa cambia:
--   * Nuova tabella "print-farm"."PrintRunSpoolConsumption": una riga per
--     (printRunId, spoolId, source) con i grammi NETTI attribuiti a quella
--     bobina su quella run. Oggi il consumo per-bobina è solo transiente
--     (ricalcolato a ogni harvest da reconcileSpoolConsumption in
--     client/src/app/api/harvest/_utils/spool-consumption.ts) e il backend
--     tracker muta solo FilamentSpool.remainingWeight: niente storia.
--
-- Semantica della riga (ledger, non eventi):
--   * La UNIQUE (printRunId, spoolId, source) rende le scritture idempotenti:
--     i writer fanno UPSERT accumulando il delta
--     (gramsUsed = gramsUsed + EXCLUDED.gramsUsed). La riga tiene quindi il
--     NETTO per quella sorgente: un revert harvest (delta negativo) scala la
--     stessa riga verso zero invece di creare una contro-riga.
--   * Il consumo totale della run per bobina = SUM(gramsUsed) su tutte le
--     source. `updatedAt` traccia l'ultima attribuzione (la riga accumula).
--
-- Source note (colonna TEXT volutamente aperta, niente CHECK/enum: il backend
-- tracker aggiungerà la sua senza migration):
--   * 'harvest-reconcile'  → riconciliazione a harvest / revert (client)
--   * 'harvest-checkpoint' → congelamento consumo prima di uno swap a metà
--                            stampa (checkpointSpoolConsumptionForActiveRun)
--   * 'run-start'          → bobina presente all'avvio della run (gramsUsed=0,
--                            marcatore "chi c'era", prepara gap #2)
--   * 'manual'             → correzioni da operatore
--   * 'tracker-snapshot'   → (FUTURO, backend) deduzioni live da snapshot
--
-- Scelte FK:
--   * printRunId → ON DELETE CASCADE: il ledger è un dettaglio della run, se
--     la run sparisce le sue righe non hanno senso (come PrintRunMetrics).
--   * spoolId → ON DELETE RESTRICT: la bobina deve SOPRAVVIVERE per
--     tracciabilità ("cosa ha stampato questa bobina"); una bobina con righe
--     ledger non si cancella, si archivia (status ARCHIVED). Coerente con
--     FilamentSpool.itemId che è già Restrict.
--
-- Tipi: gramsUsed DECIMAL(12,2) come PrintRunMetrics.filamentUsedGrams
-- (stesso dominio: grammi di filamento attribuiti a una run).
--
-- Tutto additivo e idempotente (IF NOT EXISTS): nessuna tabella esistente
-- viene toccata e il codice in produzione (vecchio) ignora la nuova tabella.
--
-- Applicabile anche via psql / Supabase SQL editor. Se lo fai fuori da Prisma:
--   bunx prisma migrate resolve --applied 20260904033000_print_run_spool_ledger
--
-- ----------------------------------------------------------------------------
-- INTERFACCIA BACKEND (spool_consumption_tracker.js — modifica FUTURA, in
-- attesa di permesso): quando il tracker deduce grammi da snapshot live deve
-- replicare la stessa scrittura con source 'tracker-snapshot', nella stessa
-- transazione della deduzione di remainingWeight:
--
--   INSERT INTO "print-farm"."PrintRunSpoolConsumption"
--     ("id", "printRunId", "spoolId", "gramsUsed", "source", "createdAt", "updatedAt")
--   VALUES (gen_random_uuid(), $1, $2, $3, 'tracker-snapshot', now(), now())
--   ON CONFLICT ("printRunId", "spoolId", "source")
--   DO UPDATE SET
--     "gramsUsed" = "PrintRunSpoolConsumption"."gramsUsed" + EXCLUDED."gramsUsed",
--     "updatedAt" = now();
--
-- ($1 = printRunId, $2 = spoolId, $3 = delta grammi dello snapshot; delta
--  negativo solo in caso di correzione/ripristino esplicito.)
-- ============================================================================

CREATE TABLE IF NOT EXISTS "print-farm"."PrintRunSpoolConsumption" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "printRunId" UUID NOT NULL,
    "spoolId" UUID NOT NULL,
    -- Grammi NETTI attribuiti alla bobina per questa run+source (accumulati via upsert).
    "gramsUsed" DECIMAL(12,2) NOT NULL DEFAULT 0,
    -- Sorgente dell'attribuzione (vedi header; TEXT aperta, niente enum di proposito).
    "source" TEXT NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT now(),
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT now(),

    CONSTRAINT "PrintRunSpoolConsumption_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "PrintRunSpoolConsumption_printRunId_fkey"
        FOREIGN KEY ("printRunId") REFERENCES "print-farm"."PrintRun"("id")
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "PrintRunSpoolConsumption_spoolId_fkey"
        FOREIGN KEY ("spoolId") REFERENCES "print-farm"."FilamentSpool"("id")
        ON DELETE RESTRICT ON UPDATE CASCADE
);

-- Idempotenza dei writer: una riga per (run, bobina, sorgente).
CREATE UNIQUE INDEX IF NOT EXISTS "PrintRunSpoolConsumption_printRunId_spoolId_source_key"
    ON "print-farm"."PrintRunSpoolConsumption"("printRunId", "spoolId", "source");

-- "Cosa ha stampato questa bobina?" (vista per-bobina).
CREATE INDEX IF NOT EXISTS "PrintRunSpoolConsumption_spoolId_idx"
    ON "print-farm"."PrintRunSpoolConsumption"("spoolId");

-- "Quali bobine ha consumato questa run?" (vista per-run; la unique copre già
-- il prefisso printRunId, l'indice dedicato rende esplicito il percorso di lettura).
CREATE INDEX IF NOT EXISTS "PrintRunSpoolConsumption_printRunId_idx"
    ON "print-farm"."PrintRunSpoolConsumption"("printRunId");
