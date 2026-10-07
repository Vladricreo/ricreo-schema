-- ============================================================================
-- PrinterMaintenancePlan."windowStartMinute": manutenzioni come FINESTRE ORARIE
-- (decisione dell'utente 2026-10-07, punto 3: "le manutenzioni legacy le puoi
-- togliere e fare quelle nuove"; REVISIONE 2026-09-30 B3 = V5a-8 / V5b-F10;
-- filone D3-MAINT)
--
-- Semantica nuova (codice PF, lib/maintenance/window-placement.ts):
-- - `nextDueAt` e `PrinterMaintenanceLog.scheduledFor` sono l'INIZIO di una
--   finestra oraria concreta; la durata è `estimatedDurationMin`;
-- - la finestra si colloca all'ora preferita (questa colonna, minuti dalla
--   mezzanotte di Roma) oppure, se NULL, all'inizio del primo turno di presidio
--   (WorkShift di chi può scaricare) del giorno di scadenza o del primo giorno
--   lavorativo dopo;
-- - `graceDays` resta solo per l'evidenziazione UI: non è più un input degli
--   scheduler (la logica vecchia "giorno a mezzanotte + grazia" è rimossa).
--
-- Questa migrazione NON tocca i dati. I 15 piani esistenti vengono convertiti
-- (nuova prossima finestra collocata nel turno) dallo script, dry-run di
-- default, con backup e idempotente:
--   client/scripts/bonifica-2026-10-manutenzioni-nuove.ts
--
-- !! DEPLOY: applicare PRIMA del deploy di PF !!
-- Il client Prisma rigenerato legge la colonna in ogni query sui piani senza
-- select esplicita. Colonna nullable senza default: il codice PF vecchio e
-- Inventory non sono toccati (ordine indifferente rispetto a Inventory).
-- Ordine: 1) migrate deploy; 2) deploy PF; 3) script dry-run, poi --apply.
--
-- Idempotente: colonna e vincolo creati solo se mancano.
-- Applicabile anche via psql / Supabase SQL editor; in quel caso:
--   bunx prisma migrate resolve --applied 20261007130000_maintenance_plan_window_start
-- ============================================================================

ALTER TABLE "print-farm"."PrinterMaintenancePlan"
  ADD COLUMN IF NOT EXISTS "windowStartMinute" INTEGER;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = 'print-farm'
      AND t.relname = 'PrinterMaintenancePlan'
      AND c.conname = 'PrinterMaintenancePlan_windowStartMinute_range'
  ) THEN
    ALTER TABLE "print-farm"."PrinterMaintenancePlan"
      ADD CONSTRAINT "PrinterMaintenancePlan_windowStartMinute_range"
      CHECK (
        "windowStartMinute" IS NULL
        OR ("windowStartMinute" >= 0 AND "windowStartMinute" < 1440)
      );
  END IF;
END
$$;

COMMENT ON COLUMN "print-farm"."PrinterMaintenancePlan"."windowStartMinute" IS
  'Ora preferita di inizio finestra di manutenzione, minuti dalla mezzanotte Europe/Rome (0-1439). NULL = inizio del primo turno di presidio del giorno di scadenza.';
COMMENT ON COLUMN "print-farm"."PrinterMaintenancePlan"."nextDueAt" IS
  'Inizio della prossima finestra oraria di manutenzione (istante concreto collocato nel turno). Durata = estimatedDurationMin.';
COMMENT ON COLUMN "print-farm"."PrinterMaintenancePlan"."graceDays" IS
  'Tolleranza in giorni dopo la fine della finestra: solo evidenziazione UI, non input degli scheduler.';
