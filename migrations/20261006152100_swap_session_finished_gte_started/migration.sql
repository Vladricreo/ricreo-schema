-- ============================================================================
-- FilamentSwapSession: la chiusura non può precedere l'apertura
-- (REVISIONE 2026-09-30, finding V2-F8; filone T7-MON)
--
-- Causa: il POST salvava startedAt con l'orologio del BROWSER mentre
-- finishedAt/lastStepAt sono scritti dal server. Con il client avanti di
-- 0,05-2 s la sessione risultava finita prima di iniziare ed elapsedSeconds
-- veniva azzerato (6 righe SWAP live, diff da -45 a -1311 ms). Il codice
-- (route swap-sessions + session-lifecycle.ts) ora limita startedAt a
-- "adesso" del server e non chiude mai prima di startedAt.
--
-- Questa migrazione NON tocca i dati. La correzione delle righe storiche è
-- nello script (dry-run di default, backup, transazione):
--   client/scripts/bonifica-2026-10-mon-swap-clock-skew.ts
--
-- !! DEPLOY ORDINATO (schema condiviso PF + Inventory) !!
-- Un CHECK, anche NOT VALID, vale subito per ogni INSERT/UPDATE: con il
-- codice PF vecchio (senza clampClientStartedAt/closingInstant) una sessione
-- aperta da un tablet con l'orologio avanti e chiusa entro ~2 s violerebbe il
-- vincolo e il PATCH risponderebbe 500 per l'intero batch di step. La pipeline
-- Inventory può eseguire `prisma migrate deploy` prima del deploy PF, quindi
-- la migrazione si auto-ordina:
--   - crea il vincolo SOLO se non esiste alcuna riga con finishedAt < startedAt
--     (DB nuovi/di sviluppo, oppure dopo lo script --apply);
--   - se le righe incoerenti ci sono ancora (live al 2026-10-06: 6) NON crea
--     nulla e lascia un NOTICE: il vincolo lo crea e lo valida lo script con
--     --apply, da eseguire DOPO il deploy del codice PF.
-- Ordine: 1) deploy codice PF (T7-MON); 2) script dry-run, poi --apply
-- (corregge le righe, crea e valida il vincolo); 3) migrate deploy (qui no-op
-- se il vincolo c'è già). Se migrate deploy gira prima (es. da Inventory) è
-- un no-op con NOTICE e il passo 2 resta valido.
--
-- Idempotente: il vincolo viene creato solo se manca; VALIDATE solo se non è
-- già valido e i dati sono puliti.
-- Applicabile anche via psql / Supabase SQL editor; in quel caso:
--   bunx prisma migrate resolve --applied 20261006152100_swap_session_finished_gte_started
-- ============================================================================

DO $$
DECLARE
  violations INT;
  constraint_exists BOOLEAN := false;
  constraint_valid BOOLEAN := false;
BEGIN
  SELECT true, c.convalidated
  INTO constraint_exists, constraint_valid
  FROM pg_constraint c
  WHERE c.conname = 'FilamentSwapSession_finished_gte_started_chk'
    AND c.conrelid = '"print-farm"."FilamentSwapSession"'::regclass;

  IF coalesce(constraint_exists, false) AND coalesce(constraint_valid, false) THEN
    RETURN;
  END IF;

  SELECT count(*) INTO violations
  FROM "print-farm"."FilamentSwapSession"
  WHERE "finishedAt" IS NOT NULL
    AND "finishedAt" < "startedAt";

  IF violations > 0 THEN
    RAISE NOTICE 'FilamentSwapSession_finished_gte_started_chk NON creato/validato: % righe con finishedAt < startedAt. Dopo il deploy del codice PF eseguire scripts/bonifica-2026-10-mon-swap-clock-skew.ts --apply (corregge le righe, crea e valida il vincolo).', violations;
    RETURN;
  END IF;

  -- Dati puliti: NOT VALID (nessuna scansione sotto ACCESS EXCLUSIVE) e poi
  -- VALIDATE (lock più leggero).
  IF NOT coalesce(constraint_exists, false) THEN
    ALTER TABLE "print-farm"."FilamentSwapSession"
      ADD CONSTRAINT "FilamentSwapSession_finished_gte_started_chk"
      CHECK ("finishedAt" IS NULL OR "finishedAt" >= "startedAt") NOT VALID;
  END IF;
  ALTER TABLE "print-farm"."FilamentSwapSession"
    VALIDATE CONSTRAINT "FilamentSwapSession_finished_gte_started_chk";
END $$;
