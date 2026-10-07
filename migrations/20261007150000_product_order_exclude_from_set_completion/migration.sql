-- ============================================================================
-- ProductOrder."excludeFromSetCompletion": ordini PRODUCED "storici", neutri
-- (REVISIONE 2026-09-30 V7-F3, decisione utente 2026-10-07 punto 5:
-- "bonifica pure tutto, e assicurati che non capiti nuovamente";
-- opzione b dei residui, FIX-2026-10-06.md §4.2; filone E1-LEGACY83)
--
-- Contesto: 83 ordini qty=0, senza AssemblyOrder, realmente prodotti (job
-- tutti FULFILLED, pezzi stampati, finishedAt valorizzato) sono CANCELLED
-- perché li ha annullati la vecchia auto-pulizia "fantasma" di
-- /api/production-orders/generate (Inventory, commit 927e8f7 → eec3b70,
-- aprile-luglio 2026: filtro PRODUCED + qty<=0 + senza AO, senza il controllo
-- sulle righe parti). Riportati a PRODUCED così come sono, 70 diventerebbero
-- candidati "completamento set" e creerebbero AssemblyOrder fantasma su pezzi
-- consumati da mesi.
--
-- Il flag li rende neutri nel codice Inventory (lib/production-orders/
-- set-completion-exclusion.ts): niente completamento set né AO, niente
-- disponibilità/allocazione per i set, niente pipeline né blocco della
-- generazione automatica. Restano visibili come ordini PRODUCED (KPI,
-- tracciabilità, attività operatore).
--
-- Nessun dato toccato: default false per tutte le righe. Il flag lo imposta
-- solo la bonifica (Inventory, dry-run di default):
--   client/scripts/bonifica-2026-10-produced-legacy-cleanup.ts
--
-- !! DEPLOY: applicare PRIMA del deploy di Inventory e PF !!
-- Il client Prisma rigenerato legge la colonna in ogni query su
-- "ProductOrder" senza select esplicita: senza la colonna quelle query
-- falliscono. Applicarla prima è innocuo (il codice vecchio non la conosce).
-- Nessun indice: le query la usano come filtro aggiuntivo (true su ~83 righe).
--
-- Idempotente: ADD COLUMN IF NOT EXISTS (con default costante: solo
-- metadati, nessuna riscrittura della tabella) + COMMENT.
-- Applicabile anche via psql / Supabase SQL editor; in quel caso:
--   bunx prisma migrate resolve --applied 20261007150000_product_order_exclude_from_set_completion
-- ============================================================================

ALTER TABLE inventory."ProductOrder"
  ADD COLUMN IF NOT EXISTS "excludeFromSetCompletion" BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN inventory."ProductOrder"."excludeFromSetCompletion" IS
  'V7-F3/E1-LEGACY83: ordine PRODUCED storico (pezzi già consumati), neutro: escluso da completamento set, AO, disponibilità per i set, pipeline e blocco della generazione automatica. Lo imposta solo la bonifica bonifica-2026-10-produced-legacy-cleanup.ts.';
