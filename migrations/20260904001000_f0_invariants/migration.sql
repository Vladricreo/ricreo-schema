-- Invarianti F0 (audit 2026-09-03: PIANO-AZIONE ondata 2, punti 2.2-2.5;
-- REPORT DB3/DB4/DB12/DB13/DB14/DB16).
--
-- Vincoli "una sola riga aperta" sulle tabelle runtime + view KPI pulite.
-- Eseguita DOPO la bonifica dati (client/scripts/bonifica-f0-data.ts e
-- bonifica-f0-swap-old-format.ts): i pre-check
-- (client/scripts/f0-invariants-check.ts) hanno verificato 0 violazioni su
-- downtime e swap; il dedupe PrinterIssue qui sotto e' una rete di sicurezza
-- idempotente (sul DB live risultava gia' a 0 duplicati).
--
-- NOTA deploy-order (il codice in produzione e' ancora quello VECCHIO):
-- - downtime: il vecchio backend apre con check-then-insert (un solo processo,
--   cache RAM anti-rientro): il vincolo scatta solo su race multi-processo.
-- - swap: la vecchia UI puo' aprire due sessioni da due tab: ora il secondo
--   POST fallisce con errore invece di creare un duplicato silenzioso.
-- - issue: il vecchio sync risolve-e-reinserisce in sequenza sulla stessa
--   stampante: mai due OPEN contemporanee per lo stesso codice.
-- - GanttPlan: l'indice esiste gia' live dal 2026-07-31, qui e' solo
--   drift-proofing (IF NOT EXISTS = no-op).
-- Il deploy del codice nuovo segue subito questa migrazione.

BEGIN;

-- ============================================================================
-- 1) PrinterDowntimeEvent: un solo downtime aperto per stampante + date coerenti
--    (DB3; pattern speculare a PrinterOverridePeriod_one_open_per_printer).
-- ============================================================================

-- Ultima barriera contro doppi eventi aperti (race/retry del check-then-insert).
CREATE UNIQUE INDEX IF NOT EXISTS "PrinterDowntimeEvent_one_open_per_printer"
  ON "print-farm"."PrinterDowntimeEvent" ("printerId")
  WHERE "resolvedAt" IS NULL;

-- Sweep/query sulle righe aperte (chiusura su uscita da ERROR/RUNOUT, dashboard).
CREATE INDEX IF NOT EXISTS "PrinterDowntimeEvent_open_openedAt_idx"
  ON "print-farm"."PrinterDowntimeEvent" ("openedAt" DESC)
  WHERE "resolvedAt" IS NULL;

-- Coerenza temporale: la chiusura non puo' precedere l'apertura.
ALTER TABLE "print-farm"."PrinterDowntimeEvent"
  ADD CONSTRAINT "PrinterDowntimeEvent_resolved_gte_opened_chk"
  CHECK ("resolvedAt" IS NULL OR "resolvedAt" >= "openedAt");

-- ============================================================================
-- 2) FilamentSwapSession: una sola sessione aperta per target fisico
--    (printerId, targetKind, amsUnit, slot) — DB4.
--    NULLS NOT DISTINCT: due sessioni 'external' (amsUnit/slot NULL) sulla
--    stessa stampante devono comunque collidere.
-- ============================================================================

-- Guardia: la bonifica deve aver gia' chiuso/abbandonato le sessioni aperte.
-- Se esistono duplicati la migrazione si FERMA (niente forzature sui dati).
DO $$
DECLARE
  violations INT;
BEGIN
  SELECT count(*) INTO violations
  FROM (
    SELECT 1
    FROM "print-farm"."FilamentSwapSession"
    WHERE "finishedAt" IS NULL AND abandoned = false
    GROUP BY "printerId", "targetKind", "amsUnit", "slot"
    HAVING count(*) > 1
  ) dup;
  IF violations > 0 THEN
    RAISE EXCEPTION 'FilamentSwapSession: % gruppi target con piu'' di una sessione aperta: eseguire prima la bonifica', violations;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS "FilamentSwapSession_one_open_per_target"
  ON "print-farm"."FilamentSwapSession" ("printerId", "targetKind", "amsUnit", "slot")
  NULLS NOT DISTINCT
  WHERE "finishedAt" IS NULL AND abandoned = false;

-- ============================================================================
-- 3) PrinterIssue: una sola issue aperta per (stampante, codice) — DB12.
--    Identita' = stessa del lookup applicativo (ensureOpenPrinterIssue in
--    backend/src/services/printer_issue_sync.js): errorCodeId se mappato,
--    altrimenti externalCode. Righe con entrambi NULL: mai matchate dal
--    lookup, restano fuori dal vincolo (NULL distinti), coerente col codice.
-- ============================================================================

-- Dedupe onesto dello storico (churn open→resolve→insert del vecchio sync):
-- tiene la issue aperta PIU' VECCHIA, risolve le altre con
-- resolvedAt = propria lastSeenAt (mai una data inventata) + marker grepabile.
DO $$
DECLARE
  deduped INT;
BEGIN
  WITH open_ranked AS (
    SELECT i.id,
           i."lastSeenAt",
           ROW_NUMBER() OVER (
             PARTITION BY i."printerId",
                          COALESCE(i."errorCodeId"::text, i."externalCode")
             ORDER BY i."openedAt" ASC, i.id ASC
           ) AS rn
    FROM "print-farm"."PrinterIssue" i
    WHERE i.status IN ('OPEN', 'ACKED')
      AND COALESCE(i."errorCodeId"::text, i."externalCode") IS NOT NULL
  )
  UPDATE "print-farm"."PrinterIssue" i
  SET status = 'RESOLVED',
      "resolvedAt" = COALESCE(r."lastSeenAt", now()),
      "resolvedBy" = 'f0-invariants-dedupe',
      metadata = COALESCE(i.metadata, '{}'::jsonb)
                 || '{"dedupeSource":"f0-invariants-20260904"}'::jsonb,
      "updatedAt" = now()
  FROM open_ranked r
  WHERE i.id = r.id
    AND r.rn > 1;
  GET DIAGNOSTICS deduped = ROW_COUNT;
  RAISE NOTICE 'PrinterIssue dedupe: % righe risolte', deduped;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS "PrinterIssue_one_open_per_code"
  ON "print-farm"."PrinterIssue"
     ("printerId", (COALESCE("errorCodeId"::text, "externalCode")))
  WHERE status IN (
    'OPEN'::"print-farm"."PrinterIssueStatus",
    'ACKED'::"print-farm"."PrinterIssueStatus"
  );

-- ============================================================================
-- 4) View KPI (DB13/DB14): conteggi solo su sessioni CHIUSE; statistiche di
--    attesa solo con detectedAt onesto (i NULL storici restano esclusi invece
--    di produrre waitSeconds=0 fasulli). I conteggi grezzi restano disponibili
--    nelle nuove colonne in coda (rawSessionsCount, openCount): CREATE OR
--    REPLACE puo' solo aggiungere colonne alla fine, le esistenti restano
--    identiche in nome/ordine/tipo.
-- ============================================================================

CREATE OR REPLACE VIEW "print_farm_views"."v_pf_filament_swap_time_30d" AS
SELECT
    s."trigger"::TEXT                                              AS "trigger",
    -- Solo sessioni CHIUSE: le aperte non sono misure complete.
    COUNT(*) FILTER (WHERE s."finishedAt" IS NOT NULL)::INT        AS "sessionsCount",
    COUNT(*) FILTER (WHERE s."abandoned")::INT                     AS "abandonedCount",
    COALESCE(ROUND(AVG(s."workSeconds") FILTER (
        WHERE s."finishedAt" IS NOT NULL AND NOT s."abandoned"
    ), 2), 0)::NUMERIC(12, 2)                                      AS "avgWorkSeconds",
    COALESCE(ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY s."workSeconds"
    ) FILTER (
        WHERE s."finishedAt" IS NOT NULL AND NOT s."abandoned"
    )::NUMERIC, 2), 0)::NUMERIC(12, 2)                             AS "medianWorkSeconds",
    -- Attesa solo su righe chiuse con detectedAt onesto.
    COALESCE(ROUND(AVG(s."waitSeconds") FILTER (
        WHERE s."finishedAt" IS NOT NULL AND NOT s."abandoned"
          AND s."detectedAt" IS NOT NULL AND s."waitSeconds" IS NOT NULL
    ), 2), 0)::NUMERIC(12, 2)                                      AS "avgWaitSeconds",
    COALESCE(SUM(s."workSeconds") FILTER (
        WHERE s."finishedAt" IS NOT NULL AND NOT s."abandoned"
    ), 0)::INT                                                     AS "totalWorkSeconds",
    -- Diagnostica: conteggi grezzi (includono aperte/abbandonate).
    COUNT(*)::INT                                                  AS "rawSessionsCount",
    COUNT(*) FILTER (
        WHERE s."finishedAt" IS NULL AND NOT s."abandoned"
    )::INT                                                         AS "openCount"
FROM "print-farm"."FilamentSwapSession" s
WHERE s."startedAt" >= NOW() - INTERVAL '30 days'
GROUP BY s."trigger";

COMMENT ON VIEW "print_farm_views"."v_pf_filament_swap_time_30d" IS
  'Tempi operatore swap/runout (30gg). sessionsCount = solo sessioni CHIUSE (finishedAt NOT NULL); avgWaitSeconds solo con detectedAt onesto; rawSessionsCount/openCount = conteggi grezzi per diagnostica.';

CREATE OR REPLACE VIEW "print_farm_views"."v_pf_filament_swap_by_operator_30d" AS
SELECT
    s."operatorUserId"                                             AS "operatorUserId",
    COALESCE(NULLIF(TRIM(u."name"), ''), u."email", 'Operatore')   AS "operatorName",
    COUNT(*) FILTER (WHERE s."finishedAt" IS NOT NULL)::INT        AS "sessionsCount",
    COUNT(*) FILTER (
        WHERE s."finishedAt" IS NOT NULL AND s."trigger" = 'RUNOUT'
    )::INT                                                         AS "runoutCount",
    COUNT(*) FILTER (
        WHERE s."finishedAt" IS NOT NULL AND s."trigger" = 'SWAP'
    )::INT                                                         AS "swapCount",
    COALESCE(ROUND(AVG(s."workSeconds") FILTER (
        WHERE s."finishedAt" IS NOT NULL AND NOT s."abandoned"
    ), 2), 0)::NUMERIC(12, 2)                                      AS "avgWorkSeconds",
    COUNT(*)::INT                                                  AS "rawSessionsCount",
    COUNT(*) FILTER (
        WHERE s."finishedAt" IS NULL AND NOT s."abandoned"
    )::INT                                                         AS "openCount"
FROM "print-farm"."FilamentSwapSession" s
JOIN "public"."User" u ON u."id" = s."operatorUserId"
WHERE s."startedAt" >= NOW() - INTERVAL '30 days'
GROUP BY s."operatorUserId", u."name", u."email";

COMMENT ON VIEW "print_farm_views"."v_pf_filament_swap_by_operator_30d" IS
  'Tempi operatore swap/runout per operatore (30gg). Conteggi solo su sessioni CHIUSE; rawSessionsCount/openCount = conteggi grezzi per diagnostica.';

-- v_pf_downtime_daily_30d: spostata da client/prisma/sql-runs/print_farm_views.sql
-- (applicazione manuale = drift, DB14) dentro una migrazione versionata.
-- Definizione INVARIATA rispetto al file sql-runs.
--
-- Logica di calcolo:
--  • Cap anti-orfano: gli eventi senza "resolvedAt" sono limitati a max 24h
--    dall'apertura (LEAST(NOW(), openedAt + 24h)), cosi' un evento mai chiuso
--    non gonfia indefinitamente il giorno di apertura.
--  • Spalmatura per giorno: la durata di ogni evento viene distribuita sui
--    giorni effettivamente coperti calcolando l'overlap reale.
--  • Sottrazione manutenzione: per ogni "fetta giornaliera" si sottrae
--    l'overlap con le finestre di PrinterMaintenanceLog della stessa stampante
--    (sessioni CANCELLED escluse, cap 24h anche per manutenzioni senza endedAt).
--  • "eventsCount" = numero di eventi APERTI quel giorno.
CREATE OR REPLACE VIEW "print_farm_views"."v_pf_downtime_daily_30d" AS
WITH date_series AS (
  SELECT generate_series(
    (CURRENT_DATE - INTERVAL '29 days')::DATE,
    CURRENT_DATE,
    '1 day'::INTERVAL
  )::DATE AS day
),
-- Normalizza ogni evento con start/end effettivi.
-- Pre-filtro ampio (60gg) per intercettare anche eventi aperti prima della
-- finestra ma ancora attivi (nel limite del cap 24h).
events_normalized AS (
  SELECT
    d."id"         AS event_id,
    d."printerId"  AS printer_id,
    d."openedAt"   AS event_start,
    COALESCE(
      d."resolvedAt",
      LEAST(NOW(), d."openedAt" + INTERVAL '24 hours')
    ) AS event_end
  FROM "print-farm"."PrinterDowntimeEvent" d
  WHERE d."openedAt" >= NOW() - INTERVAL '60 days'
    AND COALESCE(d."resolvedAt", NOW()) >= NOW() - INTERVAL '30 days'
),
-- Conta eventi APERTI per giorno (semantica "nuovi fermi del giorno").
daily_events AS (
  SELECT
    DATE(event_start) AS day,
    COUNT(*)::INT     AS events_count
  FROM events_normalized
  WHERE DATE(event_start) >= (CURRENT_DATE - INTERVAL '29 days')::DATE
  GROUP BY DATE(event_start)
),
-- Finestre di manutenzione "effettive" (workflow ISO).
-- Cap 24h per sessioni senza endedAt; CANCELLED escluse.
maintenance_windows AS (
  SELECT
    m."printerId" AS printer_id,
    m."startedAt" AS m_start,
    COALESCE(
      m."endedAt",
      LEAST(NOW(), m."startedAt" + INTERVAL '24 hours')
    ) AS m_end
  FROM "print-farm"."PrinterMaintenanceLog" m
  WHERE m."startedAt" IS NOT NULL
    AND m."startedAt" >= NOW() - INTERVAL '60 days'
    AND (m."status" IS NULL OR m."status" <> 'CANCELLED')
),
-- Una "fetta" per ciascun giorno coperto da ciascun evento.
event_slices AS (
  SELECT
    e.event_id,
    e.printer_id,
    gs::DATE AS day,
    GREATEST(e.event_start, gs)                AS slice_start,
    LEAST(e.event_end, gs + INTERVAL '1 day')  AS slice_end
  FROM events_normalized e
  CROSS JOIN LATERAL generate_series(
    DATE_TRUNC('day', e.event_start),
    DATE_TRUNC('day', e.event_end),
    '1 day'::INTERVAL
  ) gs
  WHERE gs::DATE >= (CURRENT_DATE - INTERVAL '29 days')::DATE
    AND gs::DATE <= CURRENT_DATE
),
-- Per ogni fetta, sottrai i minuti coperti da una manutenzione della stessa
-- stampante (somma degli overlap; assumiamo finestre di manutenzione non
-- sovrapposte fra loro per la stessa stampante).
slice_with_maintenance AS (
  SELECT
    s.event_id,
    s.day,
    EXTRACT(EPOCH FROM (s.slice_end - s.slice_start)) / 60 AS slice_minutes,
    COALESCE(SUM(
      GREATEST(
        EXTRACT(EPOCH FROM (
          LEAST(s.slice_end, mw.m_end) - GREATEST(s.slice_start, mw.m_start)
        )) / 60,
        0
      )
    ), 0) AS maintenance_minutes
  FROM event_slices s
  LEFT JOIN maintenance_windows mw
    ON mw.printer_id = s.printer_id
   AND mw.m_end   > s.slice_start
   AND mw.m_start < s.slice_end
  GROUP BY s.event_id, s.day, s.slice_start, s.slice_end
),
daily_minutes AS (
  SELECT
    day,
    SUM(GREATEST(slice_minutes - maintenance_minutes, 0))::NUMERIC AS downtime_minutes
  FROM slice_with_maintenance
  GROUP BY day
)
SELECT
  ds.day,
  COALESCE(de.events_count, 0)                      AS "eventsCount",
  COALESCE(ROUND(dm.downtime_minutes, 2), 0)        AS "downtimeMinutes"
FROM date_series ds
LEFT JOIN daily_events  de ON de.day = ds.day
LEFT JOIN daily_minutes dm ON dm.day = ds.day
ORDER BY ds.day;

COMMENT ON VIEW "print_farm_views"."v_pf_downtime_daily_30d" IS
  'Downtime NON pianificato giornaliero fleet-wide (30 giorni). eventsCount = eventi APERTI quel giorno; downtimeMinutes = minuti di overlap reale spalmati sui giorni coperti, MENO l''overlap con le finestre di PrinterMaintenanceLog (sessioni CANCELLED escluse). Cap anti-orfano 24h su eventi e manutenzioni non chiusi.';

-- ============================================================================
-- 5) GanttPlan: un solo piano ACTIVE (drift-proofing, DB16).
--    L'indice esiste gia' dalla migrazione 20260731203000_scheduler_f6_gantt_source:
--    IF NOT EXISTS = no-op se presente, lo ricrea se droppato a mano.
--    NON dichiarabile in Prisma come @@unique([status]) (bloccherebbe piu'
--    piani SUPERSEDED/FAILED, REPORT §4.7): resta solo SQL; il modello
--    GanttPlan in print-farm.prisma riporta un commento di avviso.
-- ============================================================================

CREATE UNIQUE INDEX IF NOT EXISTS "GanttPlan_single_active_idx"
  ON "print-farm"."GanttPlan"("status")
  WHERE "status" = 'ACTIVE';

COMMIT;
