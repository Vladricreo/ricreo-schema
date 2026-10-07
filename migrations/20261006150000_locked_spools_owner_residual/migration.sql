-- ============================================================================
-- v_pf_locked_spools_for_swap in migrazione (A9) + lock con proprietario e
-- domanda solo residua (A4, revisione 2026-09-30 V4b-3 / V4b-8).
--
-- Base: definizione live al 2026-10-06 (= script
-- client/prisma/scripts/v_pf_locked_spools_for_swap.sql di 2aed36f8, con il
-- filtro slot_plan solo SCHEDULED). Cambia solo:
--
-- 1. Grammi di domanda (servono SOLO alle riserve a scaffale):
--    - PRINTING  → quota non ancora stampata: job × (1 − lastSnapshotPercent
--                  della run IN_PROGRESS). Prima contava il job intero;
--    - TO_HARVEST → 0 g: la stampa è finita, non consuma più filamento;
--    - START_FAILED fermo da oltre 24 h → 0 g (default revisione: un avvio
--                  fallito e mai ripreso non tiene riservate bobine a scaffale).
--    I lock di posizione (ASSIGNMENT_SLOT / ASSIGNMENT_MATERIAL sulle bobine
--    montate) restano come prima: START_FAILED resta "in uso" (decisione R2).
-- 2. SHELF_RESERVED ha un proprietario (printerId = stampante della domanda).
--    I grammi scoperti di ogni stampante (domanda − bobine già bloccate su
--    quella stampante) formano intervalli consecutivi nel gruppo
--    categoria+colore+spec; ogni bobina a scaffale (dalla più piena) va alla
--    stampante nel cui intervallo cade il suo primo grammo. Prima il lock era
--    senza owner e nessuna stampante, nemmeno quella che lo generava, poteva
--    usare la bobina (preparation/route.ts scarta host NULL).
--
-- Stesse colonne, stessi tipi, stesso ordine → CREATE OR REPLACE, idempotente.
-- Lo script in client/prisma/scripts resta allineato a questa definizione.
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS "print_farm_views";

CREATE OR REPLACE VIEW "print_farm_views"."v_pf_locked_spools_for_swap" AS
WITH active_override AS (
  SELECT o."specId", o."itemId"
  FROM "inventory"."ItemSpecOverride" o
  WHERE o."isActive" = TRUE
    AND o."startsAt" <= NOW()
    AND (o."endsAt" IS NULL OR o."endsAt" > NOW())
),
-- Hex a 6 caratteri minuscoli, senza '#'. NULL se non è un colore esadecimale.
mounted AS (
  SELECT
    sp."id" AS spool_id,
    sp."itemId" AS item_id,
    sp."remainingWeight" AS remaining_weight,
    i."itemSpecId" AS item_spec_id,
    UPPER(BTRIM(c."name")) AS material_category,
    CASE
      WHEN col."hexCode" ~* '^#?[0-9A-Fa-f]{8}$'
        THEN LOWER(LEFT(REGEXP_REPLACE(col."hexCode", '^#', ''), 6))
      WHEN col."hexCode" ~* '^#?[0-9A-Fa-f]{6}$'
        THEN LOWER(RIGHT(REGEXP_REPLACE(col."hexCode", '^#', ''), 6))
      ELSE NULL
    END AS color_key,
    slot."printerId" AS printer_id,
    slot."amsUnit" AS ams_unit,
    slot."slot" AS slot,
    CASE
      WHEN unit."amsModel" = 'AMS_HT' OR slot."amsUnit" >= 128 THEN 'AMS_HT'
      ELSE 'AMS'
    END AS ams_kind
  FROM "print-farm"."FilamentSpool" sp
  JOIN "print-farm"."PrinterAmsSlot" slot ON slot."spoolId" = sp."id"
  JOIN "print-farm"."Printer" p ON p."id" = slot."printerId"
  JOIN "inventory"."Item" i ON i."id" = sp."itemId"
  LEFT JOIN "inventory"."Category" c ON c."id" = i."categoryId"
  LEFT JOIN "inventory"."Color" col ON col."id" = i."colorId"
  LEFT JOIN LATERAL (
    SELECT u."amsModel"
    FROM "print-farm"."PrinterAmsUnit" u
    WHERE u."id" = slot."amsUnitId"
       OR (
         slot."amsUnitId" IS NULL
         AND u."printerId" = slot."printerId"
         AND u."amsId" = slot."amsUnit"
       )
    ORDER BY (u."id" = slot."amsUnitId") DESC
    LIMIT 1
  ) unit ON TRUE
  WHERE sp."status" = 'ACTIVE'
    AND sp."remainingWeight" > 0
    AND p."manualOverrideStatus" IS NULL
    AND c."name" IS NOT NULL
),
visible_assignment AS (
  SELECT
    a."id",
    a."printerId",
    a."productionJobId",
    a."productPartId",
    a."partsExpected",
    a."materialRequired",
    a."colorRequired",
    a."startPayload",
    a."status",
    j."productPartId" AS job_part_id,
    -- Quota del job ancora da stampare: pesa solo i grammi di domanda.
    CASE
      WHEN a."status" = 'TO_HARVEST' THEN 0::numeric
      WHEN a."status" = 'START_FAILED'
        AND a."updatedAt" < NOW() - INTERVAL '24 hours' THEN 0::numeric
      WHEN a."status" = 'PRINTING'
        THEN GREATEST(1 - COALESCE(run_progress.pct, 0)::numeric / 100, 0)
      ELSE 1::numeric
    END AS remaining_ratio
  FROM "print-farm"."PrinterAssignment" a
  JOIN "print-farm"."Printer" p ON p."id" = a."printerId"
  LEFT JOIN "print-farm"."ProductionJob" j ON j."id" = a."productionJobId"
  LEFT JOIN LATERAL (
    SELECT LEAST(GREATEST(COALESCE(m."lastSnapshotPercent", 0), 0), 100) AS pct
    FROM "print-farm"."PrintRun" r
    JOIN "print-farm"."PrintRunMetrics" m ON m."printRunId" = r."id"
    WHERE a."status" = 'PRINTING'
      AND r."assignmentId" = a."id"
      AND r."status" = 'IN_PROGRESS'
    ORDER BY r."startedAt" DESC NULLS LAST
    LIMIT 1
  ) run_progress ON TRUE
  WHERE a."status" IN (
      'PRINTING',
      'QUEUED',
      'TO_HARVEST',
      'START_FAILED',
      'SCHEDULED'
    )
    AND p."manualOverrideStatus" IS NULL
),
assignment_file AS (
  SELECT
    a."id" AS assignment_id,
    COALESCE(payload_file."id", job_file."id") AS file_id,
    COALESCE(payload_file."partCount", job_file."partCount") AS part_count
  FROM visible_assignment a
  LEFT JOIN "print-farm"."ProjectThreeMFFile" payload_file
    ON payload_file."id" = CASE
      WHEN a."startPayload"->>'fileId' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        THEN (a."startPayload"->>'fileId')::uuid
      ELSE NULL
    END
  LEFT JOIN LATERAL (
    SELECT f."id", f."partCount"
    FROM "print-farm"."_JobsToFiles" jf
    JOIN "print-farm"."ProjectThreeMFFile" f ON f."id" = jf."B"
    WHERE jf."A" = a."productionJobId"
      AND payload_file."id" IS NULL
    ORDER BY f."version" DESC NULLS LAST, f."createdAt" DESC
    LIMIT 1
  ) job_file ON TRUE
),
file_demand AS (
  SELECT
    a."id" AS assignment_id,
    a."printerId" AS printer_id,
    fm."fileFilamentIndex" AS file_filament_index,
    UPPER(BTRIM(COALESCE(fm."filamentType", ic."name"))) AS material_category,
    CASE
      WHEN COALESCE(fm."colorUsed", icol."hexCode") ~* '^#?[0-9A-Fa-f]{8}$'
        THEN LOWER(LEFT(REGEXP_REPLACE(COALESCE(fm."colorUsed", icol."hexCode"), '^#', ''), 6))
      WHEN COALESCE(fm."colorUsed", icol."hexCode") ~* '^#?[0-9A-Fa-f]{6}$'
        THEN LOWER(RIGHT(REGEXP_REPLACE(COALESCE(fm."colorUsed", icol."hexCode"), '^#', ''), 6))
      ELSE NULL
    END AS color_key,
    COALESCE(
      fm."materialSpecId",
      (
        SELECT ppm."materialSpecId"
        FROM "inventory"."ProductPartMaterial" ppm
        WHERE ppm."productPartId" = COALESCE(a."productPartId", a.job_part_id)
        ORDER BY ppm."priority" ASC
        LIMIT 1
      ),
      mi."itemSpecId"
    ) AS preferred_spec_id,
    CASE
      WHEN fm."usedWeight" > 0 AND af.part_count > 0 AND a."partsExpected" > 0
        THEN ROUND((fm."usedWeight" * a."partsExpected") / af.part_count * a.remaining_ratio, 2)
      ELSE 0::numeric
    END AS needed_grams
  FROM visible_assignment a
  JOIN assignment_file af ON af.assignment_id = a."id"
  JOIN "print-farm"."ProjectFileMaterial" fm ON fm."fileId" = af.file_id
  LEFT JOIN "inventory"."Item" mi ON mi."id" = fm."materialId"
  LEFT JOIN "inventory"."Category" ic ON ic."id" = mi."categoryId"
  LEFT JOIN "inventory"."Color" icol ON icol."id" = mi."colorId"
  WHERE COALESCE(fm."filamentType", ic."name") IS NOT NULL
),
-- Assignment senza righe file: resta il materiale dichiarato sull'assignment.
fallback_demand AS (
  SELECT
    a."id" AS assignment_id,
    a."printerId" AS printer_id,
    NULL::int AS file_filament_index,
    UPPER(BTRIM(a."materialRequired")) AS material_category,
    CASE
      WHEN a."colorRequired" ~* '^#?[0-9A-Fa-f]{8}$'
        THEN LOWER(LEFT(REGEXP_REPLACE(a."colorRequired", '^#', ''), 6))
      WHEN a."colorRequired" ~* '^#?[0-9A-Fa-f]{6}$'
        THEN LOWER(RIGHT(REGEXP_REPLACE(a."colorRequired", '^#', ''), 6))
      ELSE NULL
    END AS color_key,
    (
      SELECT ppm."materialSpecId"
      FROM "inventory"."ProductPartMaterial" ppm
      WHERE ppm."productPartId" = COALESCE(a."productPartId", a.job_part_id)
      ORDER BY ppm."priority" ASC
      LIMIT 1
    ) AS preferred_spec_id,
    0::numeric AS needed_grams
  FROM visible_assignment a
  WHERE a."materialRequired" IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM file_demand fd WHERE fd.assignment_id = a."id"
    )
),
assignment_demand AS (
  SELECT * FROM file_demand
  UNION ALL
  SELECT * FROM fallback_demand
),
slot_plan AS (
  SELECT
    plan."id" AS plan_id,
    a."printerId" AS printer_id,
    plan."spoolId" AS spool_id,
    plan."itemId" AS item_id,
    plan."amsUnit" AS ams_unit,
    plan."slot" AS slot,
    plan."fileFilamentIndex" AS file_filament_index,
    a."id" AS assignment_id
  FROM "print-farm"."AssignmentSpoolPlan" plan
  JOIN visible_assignment a ON a."id" = plan."assignmentId"
  WHERE plan."status" = 'PLANNED'
    AND (plan."spoolId" IS NOT NULL OR plan."amsUnit" IS NOT NULL)
    -- Il piano vale solo per i job non ancora partiti. Per quelli in volo
    -- conta ciò che è montato davvero (ASSIGNMENT_MATERIAL): un piano
    -- rigenerato dopo l'avvio indicava bobine a scaffale mai usate,
    -- bloccandole, e lasciava libera quella che stava stampando.
    AND a."status" = 'SCHEDULED'
),
active_gantt AS (
  SELECT t."printerId", t."productionJobId", t."assignmentId",
         t."materialCategory", t."colorHex", t."partsExpected"
  FROM "print-farm"."GanttTask" t
  JOIN (
    SELECT gp."id"
    FROM "print-farm"."GanttPlan" gp
    WHERE gp."status" = 'ACTIVE'
    ORDER BY gp."createdAt" DESC
    LIMIT 1
  ) plan ON plan."id" = t."ganttPlanId"
  JOIN "print-farm"."Printer" p ON p."id" = t."printerId"
  WHERE t."isSetup" = FALSE
    AND t."taskStatus" IN ('PLANNED', 'IN_PROGRESS', 'DELAYED')
    AND t."plannedStart" < NOW() + INTERVAL '72 hours'
    AND t."materialCategory" IS NOT NULL
    AND p."manualOverrideStatus" IS NULL
    AND (
      t."assignmentId" IS NULL
      OR NOT EXISTS (
        SELECT 1 FROM visible_assignment a WHERE a."id" = t."assignmentId"
      )
    )
),
gantt_demand AS (
  SELECT
    g."printerId" AS printer_id,
    UPPER(BTRIM(g."materialCategory")) AS material_category,
    CASE
      WHEN g."colorHex" ~* '^#?[0-9A-Fa-f]{8}$'
        THEN LOWER(LEFT(REGEXP_REPLACE(g."colorHex", '^#', ''), 6))
      WHEN g."colorHex" ~* '^#?[0-9A-Fa-f]{6}$'
        THEN LOWER(RIGHT(REGEXP_REPLACE(g."colorHex", '^#', ''), 6))
      ELSE NULL
    END AS color_key,
    COALESCE(
      file_mat.material_spec_id,
      (
        SELECT ppm."materialSpecId"
        FROM "print-farm"."ProductionJob" j
        JOIN "inventory"."ProductPartMaterial" ppm
          ON ppm."productPartId" = j."productPartId"
        WHERE j."id" = g."productionJobId"
        ORDER BY ppm."priority" ASC
        LIMIT 1
      ),
      file_mat.item_spec_id
    ) AS preferred_spec_id,
    COALESCE(file_mat.needed_grams, 0::numeric) AS needed_grams
  FROM active_gantt g
  LEFT JOIN LATERAL (
    SELECT
      fm."materialSpecId" AS material_spec_id,
      mi."itemSpecId" AS item_spec_id,
      CASE
        WHEN fm."usedWeight" > 0 AND f."partCount" > 0 AND g."partsExpected" > 0
          THEN ROUND((fm."usedWeight" * g."partsExpected") / f."partCount", 2)
        ELSE 0::numeric
      END AS needed_grams
    FROM "print-farm"."_JobsToFiles" jf
    JOIN "print-farm"."ProjectThreeMFFile" f ON f."id" = jf."B"
    JOIN "print-farm"."ProjectFileMaterial" fm ON fm."fileId" = f."id"
    LEFT JOIN "inventory"."Item" mi ON mi."id" = fm."materialId"
    LEFT JOIN "inventory"."Category" ic ON ic."id" = mi."categoryId"
    WHERE jf."A" = g."productionJobId"
      AND UPPER(BTRIM(COALESCE(fm."filamentType", ic."name")))
        = UPPER(BTRIM(g."materialCategory"))
    ORDER BY f."version" DESC NULLS LAST
    LIMIT 1
  ) file_mat ON TRUE
),
locked_slot AS (
  SELECT
    COALESCE(plan.spool_id, slot_spool.spool_id) AS spool_id,
    COALESCE(sp."itemId", plan.item_id, slot_spool.item_id) AS item_id,
    COALESCE(sp."remainingWeight", slot_spool.remaining_weight, 0) AS remaining_weight,
    COALESCE(
      demand.preferred_spec_id,
      plan_item."itemSpecId",
      sp_item."itemSpecId",
      slot_spool.item_spec_id
    ) AS preferred_spec_id,
    COALESCE(
      demand.material_category,
      slot_spool.material_category,
      UPPER(BTRIM(ic."name"))
    ) AS material_category,
    COALESCE(demand.color_key, slot_spool.color_key) AS color_key,
    'ASSIGNMENT_SLOT' AS lock_source,
    plan.printer_id,
    COALESCE(slot_spool.ams_unit, plan.ams_unit) AS ams_unit,
    COALESCE(slot_spool.slot, plan.slot) AS slot,
    COALESCE(slot_spool.ams_kind, 'SHELF') AS ams_kind
  FROM slot_plan plan
  LEFT JOIN assignment_demand demand
    ON demand.assignment_id = plan.assignment_id
   AND demand.file_filament_index IS NOT DISTINCT FROM plan.file_filament_index
  LEFT JOIN mounted slot_spool
    ON slot_spool.printer_id = plan.printer_id
   AND slot_spool.ams_unit = plan.ams_unit
   AND slot_spool.slot = plan.slot
  LEFT JOIN "print-farm"."FilamentSpool" sp ON sp."id" = plan.spool_id
  LEFT JOIN "inventory"."Item" sp_item ON sp_item."id" = sp."itemId"
  LEFT JOIN "inventory"."Item" plan_item ON plan_item."id" = plan.item_id
  LEFT JOIN "inventory"."Category" ic ON ic."id" = COALESCE(sp_item."categoryId", plan_item."categoryId")
  WHERE COALESCE(plan.spool_id, slot_spool.spool_id) IS NOT NULL
),
locked_assignment_material AS (
  SELECT
    m.spool_id,
    m.item_id,
    m.remaining_weight,
    d.preferred_spec_id,
    m.material_category,
    m.color_key,
    'ASSIGNMENT_MATERIAL' AS lock_source,
    m.printer_id,
    m.ams_unit,
    m.slot,
    m.ams_kind
  FROM mounted m
  JOIN assignment_demand d
    ON d.printer_id = m.printer_id
   AND d.material_category = m.material_category
   AND (d.color_key IS NULL OR d.color_key = m.color_key)
  WHERE NOT EXISTS (
    SELECT 1
    FROM slot_plan plan
    WHERE plan.assignment_id = d.assignment_id
      AND plan.file_filament_index IS NOT DISTINCT FROM d.file_filament_index
  )
),
locked_gantt AS (
  SELECT
    m.spool_id,
    m.item_id,
    m.remaining_weight,
    d.preferred_spec_id,
    m.material_category,
    m.color_key,
    'GANTT_MATERIAL' AS lock_source,
    m.printer_id,
    m.ams_unit,
    m.slot,
    m.ams_kind
  FROM mounted m
  JOIN gantt_demand d
    ON d.printer_id = m.printer_id
   AND d.material_category = m.material_category
   AND (d.color_key IS NULL OR d.color_key = m.color_key)
),
position_locks AS (
  SELECT * FROM locked_slot
  UNION ALL
  SELECT * FROM locked_assignment_material
  UNION ALL
  SELECT * FROM locked_gantt
),
-- Grammi ancora da stampare per stampante e gruppo materiale.
printer_demand AS (
  SELECT
    demand.printer_id,
    demand.material_category,
    demand.color_key,
    demand.preferred_spec_id,
    SUM(demand.needed_grams) AS needed_grams
  FROM (
    SELECT printer_id, material_category, color_key, preferred_spec_id, needed_grams
    FROM assignment_demand
    UNION ALL
    SELECT printer_id, material_category, color_key, preferred_spec_id, needed_grams
    FROM gantt_demand
  ) demand
  WHERE demand.material_category IS NOT NULL
    AND demand.needed_grams > 0
  GROUP BY demand.printer_id, demand.material_category, demand.color_key, demand.preferred_spec_id
),
demand_grams AS (
  SELECT
    material_category,
    color_key,
    preferred_spec_id,
    SUM(needed_grams) AS needed_grams
  FROM printer_demand
  GROUP BY material_category, color_key, preferred_spec_id
),
-- Grammi già sulle AMS bloccate, una volta per bobina e per spec.
covered_grams AS (
  SELECT
    locks.material_category,
    locks.color_key,
    locks.preferred_spec_id,
    SUM(locks.remaining_weight) AS covered_grams
  FROM (
    SELECT DISTINCT ON (spool_id, material_category, color_key, preferred_spec_id)
      spool_id,
      material_category,
      color_key,
      preferred_spec_id,
      remaining_weight
    FROM position_locks
    WHERE material_category IS NOT NULL
    ORDER BY spool_id, material_category, color_key, preferred_spec_id
  ) locks
  GROUP BY locks.material_category, locks.color_key, locks.preferred_spec_id
),
residual AS (
  SELECT
    d.material_category,
    d.color_key,
    d.preferred_spec_id,
    GREATEST(d.needed_grams - COALESCE(c.covered_grams, 0), 0) AS residual_grams
  FROM demand_grams d
  LEFT JOIN covered_grams c
    ON c.material_category = d.material_category
   AND c.color_key IS NOT DISTINCT FROM d.color_key
   AND c.preferred_spec_id IS NOT DISTINCT FROM d.preferred_spec_id
  WHERE d.needed_grams > COALESCE(c.covered_grams, 0)
),
-- Stessa copertura, per stampante: le bobine bloccate su una macchina coprono
-- la sua domanda.
printer_covered AS (
  SELECT
    locks.printer_id,
    locks.material_category,
    locks.color_key,
    locks.preferred_spec_id,
    SUM(locks.remaining_weight) AS covered_grams
  FROM (
    SELECT DISTINCT ON (spool_id, printer_id, material_category, color_key, preferred_spec_id)
      spool_id,
      printer_id,
      material_category,
      color_key,
      preferred_spec_id,
      remaining_weight
    FROM position_locks
    WHERE material_category IS NOT NULL
      AND printer_id IS NOT NULL
    ORDER BY spool_id, printer_id, material_category, color_key, preferred_spec_id
  ) locks
  GROUP BY locks.printer_id, locks.material_category, locks.color_key, locks.preferred_spec_id
),
-- Grammi scoperti per stampante, in intervalli consecutivi dentro il gruppo:
-- [gap_end - gap_grams, gap_end). Prima la stampante più scoperta.
printer_gap AS (
  SELECT
    g.printer_id,
    g.material_category,
    g.color_key,
    g.preferred_spec_id,
    g.gap_grams,
    SUM(g.gap_grams) OVER (
      PARTITION BY g.material_category, g.color_key, g.preferred_spec_id
      ORDER BY g.gap_grams DESC, g.printer_id
    ) AS gap_end
  FROM (
    SELECT
      d.printer_id,
      d.material_category,
      d.color_key,
      d.preferred_spec_id,
      GREATEST(d.needed_grams - COALESCE(c.covered_grams, 0), 0) AS gap_grams
    FROM printer_demand d
    LEFT JOIN printer_covered c
      ON c.printer_id = d.printer_id
     AND c.material_category = d.material_category
     AND c.color_key IS NOT DISTINCT FROM d.color_key
     AND c.preferred_spec_id IS NOT DISTINCT FROM d.preferred_spec_id
  ) g
  WHERE g.gap_grams > 0
),
shelf AS (
  SELECT
    sp."id" AS spool_id,
    sp."itemId" AS item_id,
    sp."remainingWeight" AS remaining_weight,
    i."itemSpecId" AS item_spec_id,
    UPPER(BTRIM(c."name")) AS material_category,
    CASE
      WHEN col."hexCode" ~* '^#?[0-9A-Fa-f]{8}$'
        THEN LOWER(LEFT(REGEXP_REPLACE(col."hexCode", '^#', ''), 6))
      WHEN col."hexCode" ~* '^#?[0-9A-Fa-f]{6}$'
        THEN LOWER(RIGHT(REGEXP_REPLACE(col."hexCode", '^#', ''), 6))
      ELSE NULL
    END AS color_key
  FROM "print-farm"."FilamentSpool" sp
  JOIN "inventory"."Item" i ON i."id" = sp."itemId"
  LEFT JOIN "inventory"."Category" c ON c."id" = i."categoryId"
  LEFT JOIN "inventory"."Color" col ON col."id" = i."colorId"
  WHERE sp."status" = 'ACTIVE'
    AND sp."mountedOnId" IS NULL
    AND sp."remainingWeight" > 0
    AND NOT EXISTS (
      SELECT 1 FROM "print-farm"."PrinterAmsSlot" slot WHERE slot."spoolId" = sp."id"
    )
    AND NOT EXISTS (
      SELECT 1
      FROM "print-farm"."PrinterExternalSpool" ext
      WHERE ext."spoolId" = sp."id"
    )
    AND NOT EXISTS (
      SELECT 1 FROM "print-farm"."Printer" host
      WHERE host."currentSpoolId" = sp."id"
    )
    AND c."name" IS NOT NULL
),
shelf_ranked AS (
  SELECT
    s.spool_id,
    s.item_id,
    s.remaining_weight,
    r.preferred_spec_id,
    s.material_category,
    s.color_key,
    r.color_key AS demand_color_key,
    r.residual_grams,
    SUM(s.remaining_weight) OVER (
      PARTITION BY s.material_category, r.color_key, r.preferred_spec_id
      ORDER BY s.remaining_weight DESC, s.spool_id
    ) AS running_grams
  FROM shelf s
  JOIN residual r
    ON r.material_category = s.material_category
   AND (r.color_key IS NULL OR r.color_key = s.color_key)
   AND (
     r.preferred_spec_id IS NULL
     OR s.item_spec_id = r.preferred_spec_id
     OR EXISTS (
       SELECT 1
       FROM active_override o
       WHERE o."specId" = r.preferred_spec_id
         AND o."itemId" = s.item_id
     )
   )
  WHERE NOT EXISTS (
    SELECT 1 FROM position_locks pl WHERE pl.spool_id = s.spool_id
  )
),
locked_shelf AS (
  SELECT
    sr.spool_id,
    sr.item_id,
    sr.remaining_weight,
    sr.preferred_spec_id,
    sr.material_category,
    sr.color_key,
    'SHELF_RESERVED' AS lock_source,
    -- Proprietario: la stampante nel cui intervallo scoperto cade il primo
    -- grammo della bobina; in mancanza (coperture sovrapposte fra stampanti)
    -- quella con più domanda nel gruppo.
    COALESCE(
      (
        SELECT g.printer_id
        FROM printer_gap g
        WHERE g.material_category = sr.material_category
          AND g.color_key IS NOT DISTINCT FROM sr.demand_color_key
          AND g.preferred_spec_id IS NOT DISTINCT FROM sr.preferred_spec_id
          AND g.gap_end > sr.running_grams - sr.remaining_weight
        ORDER BY g.gap_end ASC
        LIMIT 1
      ),
      (
        SELECT d.printer_id
        FROM printer_demand d
        WHERE d.material_category = sr.material_category
          AND d.color_key IS NOT DISTINCT FROM sr.demand_color_key
          AND d.preferred_spec_id IS NOT DISTINCT FROM sr.preferred_spec_id
        ORDER BY d.needed_grams DESC, d.printer_id
        LIMIT 1
      )
    ) AS printer_id,
    NULL::int AS ams_unit,
    NULL::int AS slot,
    'SHELF' AS ams_kind
  FROM shelf_ranked sr
  WHERE sr.running_grams - sr.remaining_weight < sr.residual_grams
),
all_locks AS (
  SELECT
    spool_id,
    item_id,
    remaining_weight,
    preferred_spec_id,
    material_category,
    color_key,
    lock_source,
    printer_id,
    ams_unit,
    slot,
    ams_kind,
    CASE lock_source
      WHEN 'ASSIGNMENT_SLOT' THEN 1
      WHEN 'ASSIGNMENT_MATERIAL' THEN 2
      WHEN 'GANTT_MATERIAL' THEN 3
      ELSE 4
    END AS lock_rank
  FROM (
    SELECT * FROM position_locks
    UNION ALL
    SELECT * FROM locked_shelf
  ) combined
  WHERE spool_id IS NOT NULL
)
SELECT DISTINCT ON (locks.spool_id)
  locks.spool_id AS "spoolId",
  locks.item_id AS "itemId",
  locks.material_category AS "materialCategory",
  CASE
    WHEN locks.color_key IS NULL THEN NULL
    ELSE '#' || locks.color_key
  END AS "colorHex",
  locks.preferred_spec_id AS "preferredItemSpecId",
  locks.remaining_weight AS "remainingWeight",
  locks.lock_source AS "lockSource",
  locks.printer_id AS "printerId",
  locks.ams_unit AS "amsUnit",
  locks.slot AS "slot",
  locks.ams_kind AS "amsKind"
FROM all_locks locks
ORDER BY locks.spool_id, locks.lock_rank, locks.printer_id NULLS LAST;
