-- ============================================================================
-- v_pf_harvest_latency_by_hour: ora di fine stampa in Europe/Rome
--
-- REVISIONE 2026-09-30 (V5a-1 / V5a-2): la vista calcolava
-- EXTRACT(HOUR FROM finish_ts) su un timestamptz senza AT TIME ZONE, quindi
-- nell'ora della SESSIONE DB (UTC). Le fasce "notturne" risultavano spostate
-- di 1-2 ore rispetto all'orologio della farm e il lookup dell'ETA era
-- coerente solo finché il processo PF girava anch'esso in UTC.
--
-- Ora la fascia è l'ora civile Europe/Rome, esplicita e indipendente dal fuso
-- della sessione. Il COMMENT porta il marker 'tz=Europe/Rome', letto dal
-- codice (`eta/harvest-hour.ts`) per usare lo stesso fuso della vista.
-- NON impostare TZ sul container in Coolify: non serve e non va fatto.
--
-- PREREQUISITO DI RILASCIO (soddisfatto in questo ramo): i due lettori della
-- vista, eta/service.ts e admission-control.ts, cercano la riga con
-- harvestLatencyFinishHour(date, await loadHarvestLatencyHourZone()) e non
-- con getHours() del processo: leggono il marker e passano da soli all'ora di
-- Roma. Il codice nuovo funziona sia con la vista in UTC sia in ora di Roma.
-- ORDINE: nello stesso rilascio 20261006150100_swap_draft_production_job va
-- applicata PRIMA del deploy del client, quindi `migrate deploy` gira prima e
-- applica anche questa. Nella finestra fra migrazione e deploy il client
-- vecchio cerca la latenza con l'ora UTC su una vista in ora di Roma (2h di
-- sfasamento, 1h dopo il 25/10): solo le ETA/admission calcolate in quei
-- minuti, ricalcolate al giro Gantt successivo (ogni 2h). Per evitare anche
-- questa finestra: committare/applicare questa cartella in un secondo passo,
-- dopo il deploy del client PF.
-- client/prisma/sql-runs/print_farm_views.sql (sezione 13) è allineato a
-- questa definizione: rieseguirlo non riporta la vista in UTC.
--
-- Stesse colonne, stessi tipi, stesso ordine → CREATE OR REPLACE non tocca la
-- dipendente v_pf_job_eta (aggrega su tutte le ore; cambia solo la
-- ripartizione dei campioni fra le fasce).
-- Idempotente: rieseguirla riscrive la stessa definizione.
-- ============================================================================

CREATE OR REPLACE VIEW "print_farm_views"."v_pf_harvest_latency_by_hour" AS
WITH events AS (
  SELECT
    COALESCE(pr."finishedAt", a."completedAt") AS finish_ts,
    EXTRACT(EPOCH FROM (h."harvestedAt" - COALESCE(pr."finishedAt", a."completedAt"))) / 60.0 AS latency_min
  FROM "print-farm"."PrinterHarvest" h
  JOIN "print-farm"."PrinterAssignment" a ON a."id" = h."assignmentId"
  LEFT JOIN "print-farm"."PrintRun" pr ON pr."id" = h."printRunId"
  WHERE h."harvestedAt" >= NOW() - INTERVAL '3 months'
),
clean AS (
  SELECT EXTRACT(HOUR FROM (finish_ts AT TIME ZONE 'Europe/Rome'))::INT AS finish_hour, latency_min
  FROM events
  WHERE finish_ts IS NOT NULL AND latency_min >= 0 AND latency_min <= 4320
)
SELECT
  finish_hour AS "finishHour",
  ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY latency_min)::NUMERIC, 2)  AS "medianLatencyMin",
  ROUND(percentile_cont(0.25) WITHIN GROUP (ORDER BY latency_min)::NUMERIC, 2) AS "p25LatencyMin",
  ROUND(percentile_cont(0.75) WITHIN GROUP (ORDER BY latency_min)::NUMERIC, 2) AS "p75LatencyMin",
  COUNT(*)::INT AS "sampleSize"
FROM clean
GROUP BY finish_hour;

COMMENT ON VIEW "print_farm_views"."v_pf_harvest_latency_by_hour" IS
  'Latenza harvest (fine->raccolta) mediana per ora del giorno, ultimi 3 mesi. finishHour = ora civile Europe/Rome (tz=Europe/Rome).';
