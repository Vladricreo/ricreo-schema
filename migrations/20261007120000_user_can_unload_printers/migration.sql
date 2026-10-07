-- ============================================================================
-- User."canUnloadPrinters": chi può scaricare le stampanti
-- (decisione dell'utente 2026-10-07, punto 3; filone D2-PRESENCE)
--
-- Il presidio della print farm non usa più la fascia WORKHOURS (08:00-22:00,
-- riga Settings "work_hours", che resta a DB ma non viene più letta): il
-- calendario unico è WorkShift ricorrenti − WorkAbsence + OperatorExtraPresence
-- − CompanyHoliday, in ora di Roma, dei SOLI utenti attivi con questo flag
-- (client/src/lib/scheduler/operator-presence.ts del Print Farm).
--
-- Scelta: campo booleano per persona, non permesso RBAC. I ruoli RBAC dicono
-- cosa si può fare nell'app e valgono per tutti gli utenti del ruolo; qui
-- serve chi copre fisicamente il reparto (un Admin che scarica sì, un altro
-- no). Si modifica nel dialog Turni della pagina Utenti (Inventory).
--
-- Backfill dai ruoli esistenti: true per gli utenti con ruolo
-- "Operatore stampanti" o "GestoreStampanti" (lo stesso insieme che prima
-- formava il presidio del gate F1). Al 2026-10-07 risulta solo userId 5.
-- Nessun altro dato toccato.
--
-- !! DEPLOY: applicare PRIMA del deploy di PF e Inventory !!
-- Il client Prisma rigenerato legge la colonna in ogni query su "User" senza
-- select esplicita: senza la colonna quelle query falliscono.
--
-- Idempotente: colonna e backfill solo se la colonna manca. Una seconda
-- esecuzione non riscrive i flag cambiati a mano dopo il primo deploy.
-- Applicabile anche via psql / Supabase SQL editor; in quel caso:
--   bunx prisma migrate resolve --applied 20261007120000_user_can_unload_printers
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'User'
      AND column_name = 'canUnloadPrinters'
  ) THEN
    ALTER TABLE public."User"
      ADD COLUMN "canUnloadPrinters" BOOLEAN NOT NULL DEFAULT false;

    UPDATE public."User" u
    SET "canUnloadPrinters" = true
    WHERE EXISTS (
      SELECT 1
      FROM public."UserRole" ur
      JOIN public."Role" r ON r."id" = ur."roleId"
      WHERE ur."userId" = u."id"
        AND r."name" IN ('Operatore stampanti', 'GestoreStampanti')
    );
  END IF;
END
$$;

COMMENT ON COLUMN public."User"."canUnloadPrinters" IS
  'Può scaricare le stampanti: i suoi WorkShift/presenze extra formano il calendario di presidio PF (operator-presence.ts). Capacità per persona, non permesso RBAC.';
