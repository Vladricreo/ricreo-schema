-- ============================================================================
-- Ledger delle varianti per ordine in due view (richiesta utente 2026-10-08:
-- «per lo scheduler, per evitarsi tutti questi calcoli di cosa ha stampato con
-- cosa, meglio una view che calcola già in automatico e lui fa solo query»).
--
-- Stessa logica della query inline di `loadGroupVariantLedger`
-- (client/src/lib/scheduler/spool-availability/group-variant-history.ts),
-- spostata nel DB:
--
-- 1. v_pf_run_variant: una riga per run × articolo (grammi consumati) con il
--    rango per famiglia (rn = 1 = variante dominante della run per quella
--    famiglia). Esclusi i grammi col brand obbligatorio del file (decisione
--    2026-10-07: non sono la variante del gruppo).
-- 2. v_pf_group_variant_ledger: righe DONE (job × famiglia × articolo:
--    grammi e pezzi raccolti attribuiti alla variante dominante) e OPEN (run
--    non ancora raccolte: variante dei pezzi in volo, per assignment).
--
-- Due view e non una CTE condivisa: una CTE usata due volte viene
-- materializzata per intero; con le view il filtro su "jobId" /
-- "productOrderId" arriva fino a ProductionJob (indice per ordine) e poi a
-- PrintRun (indice per job). job_id e order_id sono nella PARTITION BY (sono
-- costanti per run) proprio per permettere questa spinta del filtro.
--
-- Utile anche a mano, es. brand per parte di un ordine:
--   SELECT * FROM print_farm_views.v_pf_group_variant_ledger l
--   JOIN inventory."ProductOrder" po ON po.id = l."productOrderId"
--   WHERE po.number = 1816 AND l.kind = 'DONE';
--
-- Solo view, nessun dato toccato. Applicare prima del deploy del client PF
-- (il loader legge la view; senza view torna a un ledger vuoto e logga
-- l'errore, quindi le quote per set perderebbero lo storico).
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS "print_farm_views";

CREATE OR REPLACE VIEW "print_farm_views"."v_pf_run_variant" AS
SELECT ranked.*
FROM (
  SELECT cons.*,
         ROW_NUMBER() OVER (
           PARTITION BY cons.job_id, cons.order_id, cons.run_id, COALESCE(cons.spec_id, cons.item_id)
           ORDER BY cons.grams DESC, cons.item_id
         ) AS rn
  FROM (
    SELECT pr.id AS run_id,
           j.id AS job_id,
           j."productOrderId" AS order_id,
           pr."assignmentId" AS assignment_id,
           pr."quantitySuccess" AS qs,
           pr.status::text AS run_status,
           fs."itemId" AS item_id,
           it."itemSpecId" AS spec_id,
           SUM(c."gramsUsed")::float8 AS grams
    FROM "print-farm"."ProductionJob" j
    JOIN "print-farm"."PrintRun" pr ON pr."productionJobId" = j.id
    JOIN "print-farm"."PrintRunSpoolConsumption" c ON c."printRunId" = pr.id
    JOIN "print-farm"."FilamentSpool" fs ON fs.id = c."spoolId"
    LEFT JOIN "inventory"."Item" it ON it.id = fs."itemId"
    WHERE c."gramsUsed" > 0
      AND fs."itemId" IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM "print-farm"."ProjectFileMaterial" pfm
        WHERE pfm."fileId" = pr."fileId"
          AND pfm."materialId" = fs."itemId"
          AND pfm."brandLocked" = TRUE
      )
    GROUP BY pr.id, j.id, j."productOrderId", pr."assignmentId", pr."quantitySuccess",
             pr.status, fs."itemId", it."itemSpecId"
  ) cons
) ranked;

CREATE OR REPLACE VIEW "print_farm_views"."v_pf_group_variant_ledger" AS
SELECT 'DONE'::text AS "kind",
       r.job_id AS "jobId",
       r.order_id AS "productOrderId",
       r.spec_id AS "specId",
       r.item_id AS "itemId",
       NULL::uuid AS "assignmentId",
       SUM(r.grams)::float8 AS "grams",
       SUM(CASE WHEN r.rn = 1 AND r.qs > 0 THEN r.qs ELSE 0 END)::int AS "pieces",
       j."productPartId" AS "productPartId",
       j.status::text AS "jobStatus",
       pp."quantityNeeded" AS "quantityNeeded",
       j."quantityPrinted" AS "quantityPrinted",
       j.quantity AS "quantity"
FROM "print_farm_views"."v_pf_run_variant" r
JOIN "print-farm"."ProductionJob" j ON j.id = r.job_id
LEFT JOIN "inventory"."ProductPart" pp ON pp.id = j."productPartId"
GROUP BY r.job_id, r.order_id, r.spec_id, r.item_id, j."productPartId", j.status,
         pp."quantityNeeded", j."quantityPrinted", j.quantity
UNION ALL
SELECT 'OPEN'::text,
       r.job_id,
       r.order_id,
       r.spec_id,
       r.item_id,
       r.assignment_id,
       r.grams,
       0,
       NULL::uuid,
       NULL::text,
       NULL::int,
       NULL::int,
       NULL::int
FROM "print_farm_views"."v_pf_run_variant" r
WHERE r.rn = 1
  AND r.qs = 0
  AND r.assignment_id IS NOT NULL
  AND r.run_status IN ('PENDING', 'IN_PROGRESS', 'COMPLETED');
