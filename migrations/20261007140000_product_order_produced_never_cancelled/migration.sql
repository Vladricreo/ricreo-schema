-- ============================================================================
-- ProductOrder: un ordine PRODUCED non diventa MAI CANCELLED
-- (REVISIONE 2026-09-30 V7-F3, decisione utente 2026-10-07 punto 5:
-- "bonifica pure tutto, e assicurati che non capiti nuovamente";
-- filone D4-PRODUCED)
--
-- Causa: la chiusura dell'AssemblyOrder (`cancelLeftoverQtyZeroAutoProductOrdersInTx`,
-- Inventory) annullava con un updateMany anche i completamenti qty=0 già
-- PRODUCED: 45 ordini al 2026-10-07 (l'ultimo, #1798, oggi). Il codice nuovo
-- (Inventory `lib/production-orders/produced-cancel-guard.ts`) mette la
-- guardia nella `where` di ogni writer; questo trigger è la difesa a livello
-- DB, indipendente dal codice applicativo.
--
-- Comportamento: BEFORE UPDATE OF "productionStatus", solo per la transizione
-- PRODUCED → CANCELLED. La riga resta PRODUCED (con finishedAt e
-- producedByUserId del PRODUCED, che i writer vecchi azzeravano insieme allo
-- stato) e si emette RAISE WARNING; le altre colonne dell'UPDATE si applicano.
-- NIENTE eccezione, di proposito: fra questa migrazione e il deploy gira
-- ancora il codice VECCHIO, che chiude l'AO con lo stesso updateMany; con
-- un'eccezione la chiusura dell'AO (e l'intera transazione dello stage
-- assemblato) fallirebbe con 500 per l'operatore. Così invece la chiusura
-- riesce e l'ordine prodotto resta PRODUCED.
--
-- Bypass: nessun codice applicativo lo usa (non esiste un caso d'uso
-- legittimo: la PUT Inventory risponde 409). Solo per correzioni manuali da
-- SQL editor, nella stessa transazione:
--   BEGIN;
--   SET LOCAL ricreo.allow_produced_cancel = 'on';
--   UPDATE inventory."ProductOrder" SET "productionStatus" = 'CANCELLED' WHERE id = '…';
--   COMMIT;
-- ATTENZIONE: un annullamento fatto col bypass (ordine con job tutti FULFILLED
-- e pezzi stampati) resta PER SEMPRE nella notifica HIGH
-- coverage-watch:produced-annullati: il monitor non ha un "preso atto" e
-- l'unico modo di chiuderla è riportare l'ordine a PRODUCED. Il bypass è uno
-- strumento di emergenza, non un flusso operativo.
--
-- Osservabilità: i tentativi bloccati sono nei log Postgres (Supabase → Logs,
-- livello WARNING, testo "PRODUCED -> CANCELLED bloccato"); i casi sfuggiti
-- (bypass o writer nuovi) li segnala coverage-watch
-- (`coverage-watch:produced-annullati`, HIGH con elenco, auto-resolve).
--
-- Nessun dato toccato. La bonifica dello storico è uno script a parte
-- (Inventory, dry-run di default): client/scripts/bonifica-v7-f3-produced-cancelled.ts
--
-- Idempotente: CREATE OR REPLACE FUNCTION + DROP TRIGGER IF EXISTS.
--
-- APPLICAZIONE ANTICIPATA (prima del deploy del codice, consigliata): NON
-- usare `prisma migrate deploy`, che applicherebbe anche le altre migrazioni
-- pendenti del branch fix/revisione-2026-09-30 (20261006150000…20261007130000
-- e successive) legate a codice non ancora deployato. Invece:
--   1) Supabase SQL editor (o psql): eseguire il contenuto di questo file;
--   2) da client/: bunx prisma migrate resolve --applied 20261007140000_product_order_produced_never_cancelled
--      (registra la migrazione come applicata: il futuro `migrate deploy`
--      non la riesegue; rieseguirla comunque sarebbe innocuo).
-- ============================================================================

CREATE OR REPLACE FUNCTION inventory.product_order_keep_produced()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF OLD."productionStatus" = 'PRODUCED'::inventory."ProductionStatus"
     AND NEW."productionStatus" = 'CANCELLED'::inventory."ProductionStatus"
     AND coalesce(current_setting('ricreo.allow_produced_cancel', true), '') <> 'on'
  THEN
    RAISE WARNING 'ProductOrder % (#%): PRODUCED -> CANCELLED bloccato, resta PRODUCED (V7-F3; app=%, utente=%)',
      OLD.id, OLD.number,
      coalesce(current_setting('application_name', true), ''),
      session_user;
    NEW."productionStatus" := OLD."productionStatus";
    NEW."finishedAt" := OLD."finishedAt";
    NEW."producedByUserId" := OLD."producedByUserId";
  END IF;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION inventory.product_order_keep_produced() IS
  'V7-F3: un ProductOrder PRODUCED non diventa mai CANCELLED. Mantiene PRODUCED (+ finishedAt, producedByUserId) con RAISE WARNING. Bypass solo SQL manuale: SET LOCAL ricreo.allow_produced_cancel = ''on''.';

DROP TRIGGER IF EXISTS trg_product_order_keep_produced
ON inventory."ProductOrder";

CREATE TRIGGER trg_product_order_keep_produced
BEFORE UPDATE OF "productionStatus"
ON inventory."ProductOrder"
FOR EACH ROW
WHEN (
  OLD."productionStatus" = 'PRODUCED'::inventory."ProductionStatus"
  AND NEW."productionStatus" = 'CANCELLED'::inventory."ProductionStatus"
)
EXECUTE FUNCTION inventory.product_order_keep_produced();
