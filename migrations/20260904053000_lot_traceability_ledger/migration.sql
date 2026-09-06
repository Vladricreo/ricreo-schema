-- ============================================================================
-- Tracciabilità ISO — le view preferiscono il ledger run↔spool (Ondata 7,
-- W-ISO; audit 2026-09-03: TRACCIABILITA.md gap #1 "la tabella chiave
-- mancante: per run, per bobina, grammi").
--
-- Cosa cambia:
--   * `inventory_views.v_lot_upstream_material`: la bobina della run non è più
--     solo `PrintRun.spoolId` (singolo, last-write-wins). La walk diventa
--     InventoryLot → productionLotId → ProductionJob → PrintRun →
--     "print-farm"."PrintRunSpoolConsumption" (una riga per bobina, grammi
--     netti esatti per run) → FilamentSpool → lotto materiale.
--     Fallback INVARIATO su `PrintRun.spoolId` per le run pre-ledger (nessuna
--     riga in PrintRunSpoolConsumption): il dato storico resta raggiungibile.
--   * `inventory_views.v_lot_completeness`: `missing_material_spool_link`
--     conta come "collegata" anche una run con sole righe ledger (prima
--     guardava solo `spoolId IS NOT NULL`; oggi il tracker backend scrive il
--     ledger anche quando spoolId restasse NULL).
--
-- Cardinalità: una riga per (run × bobina) invece di una per run. Le run
-- multi-materiale / con swap a metà stampa ora mostrano TUTTE le bobine
-- attribuite (prima solo l'ultima scritta in spoolId — evidenza live
-- 2026-09-04: run 22661, 104.65g totali, la view ne mostrava 21.24g sulla
-- bobina di spoolId e perdeva l'83% sul lotto materiale REALE dominante).
-- Il consumer Prisma (`VLotUpstreamMaterial`, inventory-views.prisma) usa solo
-- `findMany({ where: { lotId } })`: nessuna rottura. L'annotazione `@unique`
-- su printRunId (già falsa in produzione: stessa run su più InventoryLot dello
-- stesso ProductionLot) è corretta in `@@unique([lotId, printRunId, spoolId])`.
--
-- Bobine con soli marcatori 'run-start' (gramsUsed = 0): compaiono comunque
-- ("chi c'era" a inizio run — copre le run in corso senza harvest e prepara
-- il gap #2 sulle finestre di montaggio). I grammi netti per bobina restano
-- leggibili dalla tabella ledger / `resolvePrintRunSpoolUsage` (TS): la view
-- non espone grammi per non cambiare l'elenco colonne.
--
-- Elenco colonne IDENTICO per entrambe le view (nomi, ordine, tipi): solo
-- CREATE OR REPLACE, nessun DROP, nessun impatto sui consumer Prisma
-- (inventory-views.prisma invariato nelle colonne). Idempotente per
-- definizione (OR REPLACE). Nessuna view/matview dipende da queste due
-- (verificato su pg_depend il 2026-09-04).
--
-- NOTA sincronizzazione: la copia "reference" in Ricreo-Inventory
-- `client/prisma/custom_migrations/sql/lot_traceability_views.sql`
-- (sezioni 1 e 5) è allineata a questa migrazione: una riapplicazione
-- manuale di quel file NON deve regredire questa logica.
--
-- Applicabile anche via psql / Supabase SQL editor. Se lo fai fuori da Prisma:
--   bunx prisma migrate resolve --applied 20260904053000_lot_traceability_ledger
-- ============================================================================

-- ============================================================================
-- SEZIONE 1: Upstream materiale/produzione (ledger-first, fallback spoolId)
-- ============================================================================
CREATE OR REPLACE VIEW inventory_views.v_lot_upstream_material AS
SELECT
  il.id AS lot_id,
  il.code AS lot_code,
  pl.id AS production_lot_id,
  pl.code AS production_lot_code,
  pj.id AS production_job_id,
  pj.number AS production_job_number,
  pr.id AS print_run_id,
  pr.number AS print_run_number,
  pr."startedAt" AS print_started_at,
  pr."finishedAt" AS print_finished_at,
  pr."printerId" AS printer_id,
  printer.name AS printer_name,
  sp.id AS spool_id,
  sp."lotCode" AS spool_lot_code,
  sp."inventoryLotId" AS material_lot_id,
  ml.code AS material_lot_code,
  ml."supplierId" AS material_supplier_id,
  sup.name AS material_supplier_name,
  ml."supplierLotCode" AS material_supplier_lot_code
FROM inventory."InventoryLot" il
JOIN inventory."ProductionLot" pl ON pl.id = il."productionLotId"
JOIN "print-farm"."ProductionJob" pj ON pj."productionLotId" = pl.id
JOIN "print-farm"."PrintRun" pr ON pr."productionJobId" = pj.id
LEFT JOIN "print-farm"."Printer" printer ON printer.id = pr."printerId"
-- Risoluzione bobine della run (ledger-first, Ondata 7):
--   1) righe ledger PrintRunSpoolConsumption: una riga per bobina attribuita
--      alla run (qualunque source: 'harvest-reconcile' / 'harvest-checkpoint' /
--      'tracker-snapshot' = grammi consumati; 'run-start' a 0g = presenza a
--      inizio run). Copre multi-materiale e swap a metà stampa;
--   2) fallback legacy: `PrintRun.spoolId` SOLO se la run non ha alcuna riga
--      ledger (run precedenti all'Ondata 7).
LEFT JOIN LATERAL (
  SELECT c."spoolId" AS spool_id
  FROM "print-farm"."PrintRunSpoolConsumption" c
  WHERE c."printRunId" = pr.id
  GROUP BY c."spoolId"
  UNION ALL
  SELECT pr."spoolId"
  WHERE pr."spoolId" IS NOT NULL
    AND NOT EXISTS (
      SELECT 1
      FROM "print-farm"."PrintRunSpoolConsumption" c2
      WHERE c2."printRunId" = pr.id
    )
) rs ON true
LEFT JOIN "print-farm"."FilamentSpool" sp ON sp.id = rs.spool_id
LEFT JOIN inventory."InventoryLot" ml ON ml.id = sp."inventoryLotId"
LEFT JOIN inventory."Supplier" sup ON sup.id = ml."supplierId";

-- ============================================================================
-- SEZIONE 5: Completezza tracciabilità per lotto (report data-quality)
-- ============================================================================
CREATE OR REPLACE VIEW inventory_views.v_lot_completeness AS
SELECT
  il.id AS lot_id,
  il.code AS lot_code,
  il."originType" AS origin_type,
  -- Acquisto: manca il codice lotto fornitore
  (il."originType" = 'PURCHASE' AND il."supplierLotCode" IS NULL) AS missing_supplier_lot_code,
  -- Il collegamento all'ordine di acquisto è opzionale: molte ricezioni (scorta iniziale, acquisti
  -- "liberi" senza PO) sono legittime senza PurchaseOrderLine. Non trattarlo come gap di tracciabilità
  -- (colonna mantenuta per stabilità schema/Prisma, sempre false).
  false AS missing_purchase_order_link,
  -- Produzione: nessun printRun/spool risolto per il lotto di produzione.
  -- Una run conta "collegata" se ha `spoolId` (legacy) OPPURE almeno una riga
  -- ledger PrintRunSpoolConsumption (Ondata 7: basta anche il marcatore
  -- 'run-start' a 0g — sappiamo chi era montato anche senza harvest).
  (
    il."productionLotId" IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM "print-farm"."ProductionJob" pj
      JOIN "print-farm"."PrintRun" pr ON pr."productionJobId" = pj.id
      WHERE pj."productionLotId" = il."productionLotId"
        AND (
          pr."spoolId" IS NOT NULL
          OR EXISTS (
            SELECT 1 FROM "print-farm"."PrintRunSpoolConsumption" c
            WHERE c."printRunId" = pr.id
          )
        )
    )
  ) AS missing_material_spool_link,
  -- Movimenti sul lotto senza operatore registrato (audit trail incompleto)
  COALESCE((
    SELECT COUNT(*) FROM inventory."Movement" m
    WHERE m."lotId" = il.id AND m."byUserId" IS NULL
  ), 0)::INT AS movements_missing_operator,
  -- Nessuna ispezione qualità registrata per il lotto
  NOT EXISTS (SELECT 1 FROM inventory."LotInspection" li WHERE li."lotId" = il.id) AS missing_qc_inspection,
  -- Spedito ma senza allocazione FIFO esatta (solo legacy ShipmentLine.lotId)
  EXISTS (
    SELECT 1 FROM inventory."ShipmentLine" sl
    WHERE sl."lotId" = il.id
      AND NOT EXISTS (SELECT 1 FROM inventory."ShipmentLotAllocation" sla WHERE sla."shipmentLineId" = sl.id)
  ) AS has_legacy_only_shipment_link
FROM inventory."InventoryLot" il;
