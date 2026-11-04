-- ============================================================================
-- R-182 (04/11): slot AMS fuori uso nello scarico in una sola chiamata.
--
--   pf_harvest_context      espone `outOfServiceAmsSlots` per ogni stampante: il
--                           piano TypeScript non mappa la ristampa su quegli slot.
--   _pf_harvest_apply_item  il ripiego «primo slot con bobina» della catena ISO
--                           salta gli slot fuori uso, come resolveIsoSpoolId.
--
-- Solo CREATE OR REPLACE: corpo identico alle ultime definizioni
-- (20261028210000_harvest_rpc_combined_plate_guard per il contesto,
-- 20261029120000_harvest_rpc_skip_revert per la riga del giro) salvo le righe
-- marcate «R-182». Permessi e REVOKE restano quelli delle funzioni esistenti.
-- Da applicare dopo 20261104120000_printer_out_of_service_ams_slots.
-- ============================================================================

CREATE OR REPLACE FUNCTION "print-farm".pf_harvest_context(p_printer_ids uuid[], p_options jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb
LANGUAGE plpgsql STABLE
SET search_path = ''
AS $$
BEGIN
-- PL/pgSQL e non SQL: il piano della query resta in cache sulla connessione.
RETURN (
WITH pr AS (
  SELECT p.* FROM "print-farm"."Printer" p WHERE p.id = ANY (p_printer_ids)
),
asg AS (
  SELECT x.* FROM pr
  CROSS JOIN LATERAL (
    SELECT a.* FROM "print-farm"."PrinterAssignment" a
    WHERE a."printerId" = pr.id AND a.status IN ('TO_HARVEST', 'FAILED')
    ORDER BY a."completedAt" DESC NULLS LAST, a."updatedAt" DESC, a."createdAt" DESC
    LIMIT 5
  ) x
),
asg_json AS (
  SELECT a."printerId",
    jsonb_agg(jsonb_build_object(
      'id', a.id, 'status', a.status::text, 'updatedAt', a."updatedAt",
      'partsExpected', a."partsExpected", 'partsProduced', a."partsProduced", 'partsRejected', a."partsRejected",
      'productionJobId', a."productionJobId", 'materialRequired', a."materialRequired", 'colorRequired', a."colorRequired",
      -- A-160: piatto combinato (righe parte), da rifiutare nel piano.
      'combinedPlate', EXISTS (SELECT 1 FROM "print-farm"."PrinterAssignmentPart" pap WHERE pap."assignmentId" = a.id),
      'run', (
        SELECT jsonb_build_object(
          'id', r.id, 'status', r.status::text, 'spoolId', r."spoolId", 'fileId', r."fileId",
          'productionJobId', r."productionJobId", 'expectedQuantity', r."expectedQuantity",
          'completionPercent', r."completionPercent", 'taskFileName', r."taskFileName",
          'expectedFilamentGrams', (SELECT mm."expectedFilamentGrams" FROM "print-farm"."PrintRunMetrics" mm WHERE mm."printRunId" = r.id),
          'file', (SELECT jsonb_build_object('id', f.id, 'partCount', f."partCount",
                     'totalFilamentWeight', f."totalFilamentWeight", 'productPartId', f."productPartId")
                   FROM "print-farm"."ProjectThreeMFFile" f WHERE f.id = r."fileId"),
          'materials', coalesce((
            SELECT jsonb_agg(jsonb_build_object(
              'fileFilamentIndex', fm."fileFilamentIndex", 'fileFilamentId', fm."fileFilamentId",
              'extruderId', fm."extruderId", 'usedWeight', fm."usedWeight", 'filamentType', fm."filamentType",
              'colorUsed', fm."colorUsed", 'materialId', fm."materialId", 'trayInfoIdx', fm."trayInfoIdx")
              ORDER BY fm."fileFilamentIndex")
            FROM "print-farm"."ProjectFileMaterial" fm WHERE fm."fileId" = r."fileId"), '[]'::jsonb),
          'startPayload', (
            SELECT jsonb_strip_nulls(jsonb_build_object(
              'useAms', a2."startPayload"->'useAms', 'amsMapping', a2."startPayload"->'amsMapping',
              'amsMapping2', a2."startPayload"->'amsMapping2', 'filamentMap', a2."startPayload"->'filamentMap',
              'materialTargets', a2."startPayload"->'materialTargets', 'backupSlots', a2."startPayload"->'backupSlots'))
            FROM "print-farm"."PrinterAssignment" a2 WHERE a2.id = r."assignmentId")
        )
        FROM "print-farm"."PrintRun" r
        WHERE r."assignmentId" = a.id
        ORDER BY r."startedAt" DESC, r."createdAt" DESC
        LIMIT 1
      ),
      'job', (
        SELECT jsonb_build_object(
          'id', j.id, 'status', j.status::text, 'quantity', j.quantity, 'quantityPrinted', j."quantityPrinted",
          'productPartId', j."productPartId", 'productOrderId', j."productOrderId",
          'latestFile', (
            SELECT jsonb_build_object('id', f.id, 'filename', f.filename, 'plateNumber', f."plateNumber",
              'partCount', f."partCount", 'status', f.status::text,
              'materials', coalesce((
                SELECT jsonb_agg(jsonb_build_object(
                  'fileFilamentIndex', fm."fileFilamentIndex", 'filamentType', fm."filamentType",
                  'colorUsed', fm."colorUsed", 'categoryName', cat.name) ORDER BY fm."fileFilamentIndex")
                FROM "print-farm"."ProjectFileMaterial" fm
                LEFT JOIN inventory."Item" it ON it.id = fm."materialId"
                LEFT JOIN inventory."Category" cat ON cat.id = it."categoryId"
                WHERE fm."fileId" = f.id), '[]'::jsonb))
            FROM "print-farm"."_JobsToFiles" x JOIN "print-farm"."ProjectThreeMFFile" f ON f.id = x."B"
            WHERE x."A" = j.id ORDER BY f.version DESC LIMIT 1),
          -- Payload da cui la ristampa copia la variante dello scheduler (loadCarriedMaterialTargets):
          -- gli ultimi 10 del job, l'assignment scaricato e lo SCHEDULED della stampante.
          'payloadCandidates', coalesce((
            SELECT jsonb_agg(jsonb_build_object('id', c.id, 'startPayload', jsonb_build_object(
                     'fileId', c."startPayload"->'fileId', 'materialTargets', c."startPayload"->'materialTargets')))
            FROM (
              (SELECT pa.id, pa."startPayload" FROM "print-farm"."PrinterAssignment" pa
               WHERE pa."productionJobId" = j.id ORDER BY pa."updatedAt" DESC LIMIT 10)
              UNION
              (SELECT pa.id, pa."startPayload" FROM "print-farm"."PrinterAssignment" pa WHERE pa.id = a.id)
              UNION
              (SELECT pa.id, pa."startPayload" FROM "print-farm"."PrinterAssignment" pa
               WHERE pa."printerId" = a."printerId" AND pa.status = 'SCHEDULED'
               ORDER BY pa."queuePosition", pa."scheduledAt" NULLS LAST LIMIT 1)
            ) c
            WHERE jsonb_typeof(c."startPayload") = 'object'), '[]'::jsonb),
          'recentRuns', coalesce((
            SELECT jsonb_agg(jsonb_build_object('status', rr.status::text, 'quantitySuccess', rr."quantitySuccess",
                     'startedAt', rr."startedAt", 'finishedAt', rr."finishedAt") ORDER BY rr."finishedAt" DESC)
            FROM (
              SELECT r2.* FROM "print-farm"."PrintRun" r2
              WHERE r2."printerId" = a."printerId" AND r2."productionJobId" = j.id
                AND r2."finishedAt" IS NOT NULL
                AND r2.status::text IN ('COMPLETED', 'FAILED')
                AND NOT (r2.status::text = 'FAILED' AND r2."startedAt" IS NULL)
              ORDER BY r2."finishedAt" DESC LIMIT 2
            ) rr), '[]'::jsonb)
        )
        FROM "print-farm"."ProductionJob" j WHERE j.id = a."productionJobId"
      )
    ) ORDER BY a."completedAt" DESC NULLS LAST, a."updatedAt" DESC, a."createdAt" DESC) AS assignments
  FROM asg a
  GROUP BY a."printerId"
)
SELECT jsonb_build_object(
  'v', 1,
  'printers', coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'id', pr.id, 'name', pr.name, 'serial', pr.serial, 'locationId', pr."locationId",
      'manualOverrideStatus', pr."manualOverrideStatus"::text,
      'bedAssignmentId', pr."hasCompletedPrintOnBedAssignmentId",
      'currentSpoolId', pr."currentSpoolId", 'nozzleCount', pr."nozzleCount",
      'filaTrackSwitchInstalled', pr."filaTrackSwitchInstalled", 'ams', pr.ams,
      -- R-182: slot AMS fuori uso (colonna nullable).
      'outOfServiceAmsSlots', to_jsonb(coalesce(pr."outOfServiceAmsSlots", ARRAY[]::integer[])),
      'scheduledAssignmentId', (
        SELECT s.id FROM "print-farm"."PrinterAssignment" s
        WHERE s."printerId" = pr.id AND s.status = 'SCHEDULED'
        ORDER BY s."queuePosition", s."scheduledAt" NULLS LAST LIMIT 1),
      'assignments', coalesce(aj.assignments, '[]'::jsonb),
      'amsSlots', coalesce((
        SELECT jsonb_agg(jsonb_build_object(
          'amsUnit', s."amsUnit", 'slot', s.slot, 'spoolId', s."spoolId",
          'reportedMaterialType', s."reportedMaterialType", 'reportedColor', s."reportedColor",
          'reportedTrayInfoIdx', s."reportedTrayInfoIdx",
          'extruderId', u."extruderId", 'amsModel', u."amsModel"::text,
          'remainingWeight', sp."remainingWeight", 'spoolHasLot', sp."inventoryLotId" IS NOT NULL,
          'itemId', sp."itemId", 'itemName', it.name, 'categoryName', cat.name, 'colorHex', col."hexCode")
          ORDER BY s."amsUnit", s.slot)
        FROM "print-farm"."PrinterAmsSlot" s
        LEFT JOIN "print-farm"."PrinterAmsUnit" u ON u.id = s."amsUnitId"
        LEFT JOIN "print-farm"."FilamentSpool" sp ON sp.id = s."spoolId"
        LEFT JOIN inventory."Item" it ON it.id = sp."itemId"
        LEFT JOIN inventory."Category" cat ON cat.id = it."categoryId"
        LEFT JOIN inventory."Color" col ON col.id = it."colorId"
        WHERE s."printerId" = pr.id
          AND (s."spoolId" IS NOT NULL OR s."reportedMaterialType" IS NOT NULL OR s."reportedColor" IS NOT NULL)), '[]'::jsonb),
      'externalSpools', coalesce((
        SELECT jsonb_agg(jsonb_build_object(
          'extruderId', e."extruderId", 'spoolId', e."spoolId",
          'reportedMaterialType', e."reportedMaterialType", 'reportedColor', e."reportedColor",
          'reportedTrayInfoIdx', e."reportedTrayInfoIdx", 'itemId', sp."itemId",
          'categoryName', cat.name, 'colorHex', col."hexCode") ORDER BY e."extruderId")
        FROM "print-farm"."PrinterExternalSpool" e
        LEFT JOIN "print-farm"."FilamentSpool" sp ON sp.id = e."spoolId"
        LEFT JOIN inventory."Item" it ON it.id = sp."itemId"
        LEFT JOIN inventory."Category" cat ON cat.id = it."categoryId"
        LEFT JOIN inventory."Color" col ON col.id = it."colorId"
        WHERE e."printerId" = pr.id AND e."spoolId" IS NOT NULL), '[]'::jsonb)
    ))
    FROM pr LEFT JOIN asg_json aj ON aj."printerId" = pr.id), '[]'::jsonb),
  'odettes', coalesce((
    SELECT jsonb_agg(jsonb_build_object('id', o.id, 'code', o.code, 'status', o.status::text, 'locationId', o."locationId"))
    FROM inventory."Odette" o
    WHERE o.id IN (SELECT x::uuid FROM jsonb_array_elements_text(coalesce(p_options->'odetteIds', '[]'::jsonb)) AS e(x))), '[]'::jsonb),
  'locations', coalesce((
    SELECT jsonb_agg(jsonb_build_object('id', l.id, 'occupantIds', coalesce((
      SELECT jsonb_agg(o.id ORDER BY o.id) FROM inventory."Odette" o
      WHERE o."locationId" = l.id AND o.status::text <> 'OUT_OF_SERVICE'), '[]'::jsonb)))
    FROM inventory."WarehouseLocation" l
    WHERE l.id IN (SELECT x::uuid FROM jsonb_array_elements_text(coalesce(p_options->'locationIds', '[]'::jsonb)) AS e(x))), '[]'::jsonb)
));
END;
$$;

CREATE OR REPLACE FUNCTION "print-farm"._pf_harvest_apply_item(
  p jsonb, p_operator_id int, p_source text
) RETURNS jsonb
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  -- ingresso
  v_printer_id uuid;
  v_assignment_id uuid;
  v_expected_updated_at timestamptz;
  v_key text;
  v_req_acc int;
  v_req_rej int;
  v_reject_reason text;
  v_notes text;
  v_link_job uuid;
  v_confirmed_spool uuid;
  v_override numeric;
  v_set_maint boolean;
  v_maint_reason text;
  v_odette_in jsonb;
  v_odette_req uuid;
  v_mark_full boolean := false;
  v_move jsonb;
  v_to_location uuid;
  v_spool_plan jsonb;
  v_reprint jsonb;
  v_failure_streak boolean := false;
  v_mode text;
  v_mark_unloaded boolean := false;        -- D-09
  v_register_standalone boolean := false;  -- D-09
  v_has_harvest boolean := false;          -- D-09
  v_write_harvest boolean;                 -- D-09
  -- righe
  a record;
  pr record;
  r record;
  rf record;
  m record;
  j record;
  jf record;
  od record;
  h record;
  -- calcoli
  v_status text;
  v_already int;
  v_printed_job uuid;
  v_new_parts_expected int;
  v_new_payload jsonb;
  v_align_parts boolean := false;
  v_align_payload boolean := false;
  v_job_id uuid;
  v_link_needed boolean := false;
  v_parts_expected int;
  v_expected int;
  v_remaining int;
  v_acc int;
  v_rej int;
  v_clamped boolean;
  v_tracked boolean;
  v_part_id uuid;
  v_order_id uuid;
  v_odette_id uuid;
  v_odette_qty int;
  v_occupants uuid[];
  v_expected_occupants uuid[];
  v_iso_spool uuid;
  v_iso_spool_lot uuid;
  v_blocked boolean;
  v_lot_id uuid;
  v_inv_lot uuid;
  v_inv_lot_created boolean := false;
  v_job_before_printed int;
  v_job_before_failed int;
  v_orderpart_before int;
  v_harvest_id uuid;
  v_text text;
  v_content_id uuid;
  v_fill_id uuid;
  v_move_id uuid;
  v_from_location uuid;
  v_moved boolean := false;
  v_spool_result jsonb;
  v_total int;
  v_complete boolean;
  v_should_complete boolean;
  v_rem_after int;
  v_payload jsonb;
  v_reset boolean := false;
  v_reprint_id uuid;
  v_reprint_action text;
  v_next_queued boolean;
  v_job_after record;
  v_eoj jsonb;
  v_eoj_applied boolean := false;
  v_urgent jsonb;
  v_movement_id uuid;
  v_effects jsonb := '{}'::jsonb;
  v_verify text[] := ARRAY[]::text[];
  v_cnt int;
  v_note_prefix text;
  v_standalone_parts int;
BEGIN
  -- I record non ancora letti danno errore se se ne legge un campo: li si
  -- inizializza a NULL con la loro struttura.
  SELECT * INTO r FROM "print-farm"."PrintRun" WHERE false;
  SELECT id, "partCount", "productPartId", "totalFilamentWeight" INTO rf FROM "print-farm"."ProjectThreeMFFile" WHERE false;
  SELECT * INTO j FROM "print-farm"."ProductionJob" WHERE false;
  SELECT id, "partCount" INTO jf FROM "print-farm"."ProjectThreeMFFile" WHERE false;
  SELECT id INTO h FROM "print-farm"."PrinterHarvest" WHERE false;

  -- ===================== ingresso =====================
  v_mode := coalesce(nullif(p->>'mode', ''), 'COUNT');
  IF v_mode NOT IN ('COUNT', 'MARK_UNLOADED') THEN
    RETURN "print-farm"._pf_harvest_fail('INVALID', 'Modalità non valida: ' || v_mode, 400, false);
  END IF;
  v_mark_unloaded := v_mode = 'MARK_UNLOADED';  -- D-09
  v_register_standalone := coalesce((p->>'registerStandaloneMovements')::boolean, false);
  v_printer_id := nullif(p->>'printerId', '')::uuid;
  v_assignment_id := nullif(p->>'assignmentId', '')::uuid;
  IF v_printer_id IS NULL OR v_assignment_id IS NULL THEN
    RETURN "print-farm"._pf_harvest_fail('INVALID', 'printerId e assignmentId obbligatori', 400, false);
  END IF;
  v_expected_updated_at := nullif(p->>'expectedUpdatedAt', '')::timestamptz;
  v_key := nullif(btrim(coalesce(p->>'idempotencyKey', '')), '');
  v_req_acc := CASE WHEN (p->>'accepted') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN greatest(0, floor((p->>'accepted')::numeric))::int ELSE 0 END;
  v_req_rej := CASE WHEN (p->>'rejected') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN greatest(0, floor((p->>'rejected')::numeric))::int ELSE 0 END;
  v_reject_reason := nullif(btrim(coalesce(p->>'rejectReason', '')), '');
  v_notes := nullif(btrim(coalesce(p->>'notes', '')), '');
  v_link_job := nullif(p->>'linkProductionJobId', '')::uuid;
  v_confirmed_spool := nullif(p->>'confirmedSpoolId', '')::uuid;
  v_override := CASE WHEN (p->>'printedPercentOverride') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (p->>'printedPercentOverride')::numeric END;
  v_set_maint := coalesce((p->>'setMaintenance')::boolean, false);
  v_maint_reason := nullif(btrim(coalesce(p->>'maintenanceReason', '')), '');
  v_odette_in := CASE WHEN jsonb_typeof(p->'odette') = 'object' THEN p->'odette' END;
  IF v_odette_in IS NOT NULL THEN
    v_odette_req := nullif(v_odette_in->>'id', '')::uuid;
    v_mark_full := coalesce((v_odette_in->>'markFull')::boolean, false);
    v_move := CASE WHEN jsonb_typeof(v_odette_in->'move') = 'object' THEN v_odette_in->'move' END;
    v_to_location := nullif(v_move->>'toLocationId', '')::uuid;
  END IF;
  v_spool_plan := CASE WHEN jsonb_typeof(p->'spool') = 'object' THEN p->'spool' END;
  v_reprint := CASE WHEN jsonb_typeof(p->'reprint') = 'object' THEN p->'reprint' END;
  v_failure_streak := coalesce((v_reprint->>'failureStreak')::boolean, false);
  v_note_prefix := CASE WHEN p_source = 'DETAIL' THEN 'Scarico singolo' ELSE 'Scarico bulk progressivo' END;
  -- D-09: senza conteggio niente scarti, manutenzione, ristampa o job collegato a mano.
  -- L'odetta scelta a schermo resta: i pezzi buoni vanno lì come nello scarico (R-139).
  IF v_mark_unloaded THEN
    v_set_maint := false; v_maint_reason := NULL; v_reject_reason := NULL; v_override := NULL;
    v_reprint := NULL; v_failure_streak := false; v_link_job := NULL;
  END IF;

  -- ===================== FASE A: lock e controlli =====================
  PERFORM pg_advisory_xact_lock(hashtext(v_printer_id::text));

  SELECT * INTO a FROM "print-farm"."PrinterAssignment" WHERE id = v_assignment_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN "print-farm"._pf_harvest_fail('NOT_HARVESTABLE', 'Assegnazione non trovata o già modificata. Premi Aggiorna e riprova.', 409, false);
  END IF;
  IF a."printerId" <> v_printer_id THEN
    RETURN "print-farm"._pf_harvest_fail('NOT_HARVESTABLE', 'Assegnazione non valida per questa stampante. Premi Aggiorna e riprova.', 409, false);
  END IF;
  v_status := a.status::text;

  -- Idempotenza: chiave (colonna, o note JSON dell'ultimo giorno scritte dal percorso di prima).
  IF v_key IS NOT NULL THEN
    SELECT id, "partsAccepted", "partsRejected" INTO h
    FROM "print-farm"."PrinterHarvest" WHERE "idempotencyKey" = v_key;
    IF NOT FOUND THEN
      SELECT id, "partsAccepted", "partsRejected" INTO h
      FROM "print-farm"."PrinterHarvest"
      WHERE "harvestedAt" > now() - interval '1 day'
        AND "assignmentId" = v_assignment_id
        AND notes LIKE '{"idempotencyKey":' || to_json(v_key)::text || '%'
      ORDER BY "harvestedAt" DESC LIMIT 1;
    END IF;
    IF h.id IS NOT NULL THEN
      RETURN jsonb_build_object('ok', true, 'harvestId', h.id, 'idempotencyHit', true,
        'partsAccepted', h."partsAccepted", 'partsRejected', h."partsRejected",
        'isComplete', v_status = 'COMPLETED');
    END IF;
  END IF;

  IF v_status NOT IN ('TO_HARVEST', 'FAILED') THEN
    RETURN "print-farm"._pf_harvest_fail('NOT_HARVESTABLE',
      format('Impossibile scaricare: l''assignment è in stato "%s". %sPremi Aggiorna e riprova.', v_status,
        CASE v_status WHEN 'CANCELLED' THEN 'È stata annullata prima dello scarico. '
                      WHEN 'COMPLETED' THEN 'È già stata scaricata. '
                      ELSE 'Non è ancora pronta per lo scarico. ' END),
      409, false);
  END IF;
  IF v_expected_updated_at IS NOT NULL AND date_trunc('milliseconds', a."updatedAt") > v_expected_updated_at THEN
    RETURN "print-farm"._pf_harvest_fail('STALE', 'Questa stampante è stata scaricata o modificata da un altro operatore. Premi Aggiorna e riprova.', 409, true);
  END IF;

  SELECT id, name, serial, "manualOverrideStatus"::text AS override, "hasCompletedPrintOnBedAssignmentId" AS bed,
         "currentSpoolId", "locationId"
  INTO pr FROM "print-farm"."Printer" WHERE id = v_printer_id;
  IF NOT FOUND THEN
    RETURN "print-farm"._pf_harvest_fail('NOT_FOUND', 'Stampante non trovata', 404, false);
  END IF;
  -- D-07: il piatto deve essere di questo assignment, salvo che punti a uno non più da scaricare.
  IF pr.bed IS NOT NULL AND pr.bed <> v_assignment_id AND EXISTS (
    SELECT 1 FROM "print-farm"."PrinterAssignment" b
    WHERE b.id = pr.bed AND b.status::text IN ('TO_HARVEST', 'FAILED')
  ) THEN
    RETURN "print-farm"._pf_harvest_fail('WRONG_BED', 'L''assignment selezionata non è quella attualmente in scarico per questa stampante. Premi Aggiorna per caricare il job corretto.', 409, false);
  END IF;

  -- Ultima run dell'assignment (stesso ordinamento di Prisma: startedAt DESC = NULL prima).
  SELECT * INTO r FROM "print-farm"."PrintRun"
  WHERE "assignmentId" = v_assignment_id
  ORDER BY "startedAt" DESC, "createdAt" DESC
  LIMIT 1
  FOR UPDATE;
  IF r.id IS NOT NULL THEN
    SELECT id, "partCount", "productPartId", "totalFilamentWeight" INTO rf
    FROM "print-farm"."ProjectThreeMFFile" WHERE id = r."fileId";
    IF rf.id IS NULL AND r."taskFileName" IS NOT NULL THEN
      -- File di una stampa fuori programma dal nome mandato dalla stampante:
      -- conta solo per i pezzi attesi, non è un file «tracciato».
      SELECT f."partCount" INTO v_standalone_parts
      FROM "print-farm"."ProjectThreeMFFile" f
      WHERE f.filename = (
        SELECT CASE
          WHEN lower(b) LIKE '%.gcode.3mf' THEN b
          WHEN lower(b) LIKE '%.3mf' THEN NULL
          ELSE b || '.gcode.3mf' END
        FROM (SELECT regexp_replace(replace(btrim(r."taskFileName"), '\', '/'), '^.*/', '') AS b) s
        WHERE b <> ''
      )
      LIMIT 1;
    END IF;
    SELECT id INTO m FROM "print-farm"."PrintRunMetrics" WHERE "printRunId" = r.id FOR UPDATE;
  END IF;

  v_already := coalesce(a."partsProduced", 0) + coalesce(a."partsRejected", 0);
  v_parts_expected := a."partsExpected";

  -- Allineamento alla run (alignAssignmentToPrintedRun).
  IF r.id IS NOT NULL THEN
    v_printed_job := r."productionJobId";
    IF v_printed_job IS NULL AND r."fileId" IS NOT NULL THEN
      SELECT j2.id INTO v_printed_job
      FROM "print-farm"."_JobsToFiles" x JOIN "print-farm"."ProductionJob" j2 ON j2.id = x."A"
      WHERE x."B" = r."fileId" AND j2.status::text IN ('IN_PROGRESS', 'READY_TO_PRODUCE')
      ORDER BY j2."updatedAt" DESC LIMIT 1;
    END IF;
    IF v_printed_job IS NOT NULL AND a."productionJobId" IS NOT NULL
       AND v_printed_job <> a."productionJobId" AND v_already = 0 THEN
      RETURN "print-farm"._pf_harvest_fail('NEEDS_REPAIR', 'Assignment da riallineare al job stampato', 409, true)
        || jsonb_build_object('repair', 'align_job');
    END IF;
    IF v_already = 0 AND r."expectedQuantity" > 0 AND r."expectedQuantity" <> a."partsExpected" THEN
      v_new_parts_expected := r."expectedQuantity";
      v_align_parts := true;
      v_parts_expected := v_new_parts_expected;
    END IF;
    IF jsonb_typeof(a."startPayload") = 'object' THEN
      v_new_payload := a."startPayload";
      IF r."fileId" IS NOT NULL AND (v_new_payload->>'fileId') IS DISTINCT FROM r."fileId"::text THEN
        v_new_payload := v_new_payload || jsonb_build_object('fileId', r."fileId");
      END IF;
      IF r."taskFileName" IS NOT NULL AND r."taskFileName" <> ''
         AND (v_new_payload->>'filenameToPrint') IS DISTINCT FROM r."taskFileName" THEN
        v_new_payload := v_new_payload || jsonb_build_object('filenameToPrint', r."taskFileName");
      END IF;
      v_align_payload := v_new_payload IS DISTINCT FROM a."startPayload";
    END IF;
  END IF;

  -- Job dell'assignment (o collegato a mano dal dettaglio, stampe fuori programma).
  v_job_id := a."productionJobId";
  IF v_job_id IS NULL AND v_link_job IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM "print-farm"."ProductionJob" WHERE id = v_link_job) THEN
      RETURN "print-farm"._pf_harvest_fail('NOT_FOUND', 'Production Job selezionato non trovato', 404, false);
    END IF;
    v_job_id := v_link_job;
    v_link_needed := true;
  END IF;
  IF v_job_id IS NOT NULL THEN
    SELECT * INTO j FROM "print-farm"."ProductionJob" WHERE id = v_job_id FOR UPDATE;
    SELECT f.id, f."partCount" INTO jf
    FROM "print-farm"."_JobsToFiles" x JOIN "print-farm"."ProjectThreeMFFile" f ON f.id = x."B"
    WHERE x."A" = v_job_id ORDER BY f.version DESC LIMIT 1;
  END IF;

  -- Pezzi attesi e residuo, dalla riga bloccata.
  v_expected := CASE
    WHEN v_parts_expected > 0 THEN v_parts_expected
    WHEN r."expectedQuantity" > 0 THEN r."expectedQuantity"
    WHEN coalesce(jf."partCount", rf."partCount", v_standalone_parts) > 0
      THEN coalesce(jf."partCount", rf."partCount", v_standalone_parts)
    ELSE 0 END;
  v_remaining := greatest(0, v_expected - v_already);
  -- D-09: «Scarica» conta il residuo come buono solo se c'è dove registrarlo.
  IF v_mark_unloaded THEN
    v_has_harvest := EXISTS (SELECT 1 FROM "print-farm"."PrinterHarvest" WHERE "assignmentId" = v_assignment_id);
    v_req_acc := CASE
      WHEN v_has_harvest THEN 0
      WHEN v_job_id IS NOT NULL THEN v_remaining
      WHEN rf.id IS NOT NULL AND rf."productPartId" IS NOT NULL
           AND (coalesce(pr.override, '') <> 'MANUAL_PRINTING' OR v_register_standalone) THEN v_remaining
      ELSE 0 END;
    v_req_rej := 0;
  END IF;
  v_write_harvest := CASE WHEN v_mark_unloaded THEN NOT v_has_harvest ELSE v_remaining > 0 END;
  IF v_remaining <= 0 AND v_req_acc + v_req_rej > 0 THEN
    RETURN "print-farm"._pf_harvest_fail('ALREADY_HARVESTED',
      format('Tutti i pezzi di %s risultano già scaricati', pr.name), 409, false);
  END IF;
  v_acc := least(v_req_acc, v_remaining);
  v_rej := least(v_req_rej, v_remaining - v_acc);
  v_clamped := v_acc <> v_req_acc OR v_rej <> v_req_rej;

  -- Doppio invio negli ultimi 30 s.
  IF v_remaining > 0 THEN
    SELECT id INTO h FROM "print-farm"."PrinterHarvest"
    WHERE "assignmentId" = v_assignment_id AND "harvestedByUserId" = p_operator_id
      AND "partsAccepted" = v_acc AND "partsRejected" = v_rej
      AND "harvestedAt" >= now() - interval '30 seconds'
    ORDER BY "harvestedAt" DESC LIMIT 1;
    IF h.id IS NOT NULL THEN
      RETURN jsonb_build_object('ok', true, 'harvestId', h.id, 'idempotencyHit', true,
        'partsAccepted', v_acc, 'partsRejected', v_rej, 'isComplete', false);
    END IF;
  END IF;

  v_tracked := v_job_id IS NOT NULL OR rf.id IS NOT NULL;
  v_part_id := coalesce(j."productPartId", rf."productPartId");
  v_order_id := j."productOrderId";
  IF v_acc > 0 AND v_tracked AND v_part_id IS NULL THEN
    RETURN "print-farm"._pf_harvest_fail('INVALID_DATA', 'productPartId mancante, impossibile registrare OdetteContent e movimenti', 500, false);
  END IF;

  IF v_order_id IS NOT NULL AND v_acc > 0 THEN
    PERFORM 1 FROM inventory."ProductOrder" WHERE id = v_order_id FOR UPDATE;
  END IF;

  -- Odetta: solo con una sorgente tracciata (job o file stampato).
  v_odette_id := CASE WHEN v_tracked THEN v_odette_req END;
  IF v_odette_id IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtext('odette'), hashtext(v_odette_id::text));
    SELECT od2.id, od2.code, od2.status::text AS status, od2."locationId", t."maxPieces" INTO od
    FROM inventory."Odette" od2 LEFT JOIN inventory."OdetteType" t ON t.id = od2."typeId"
    WHERE od2.id = v_odette_id FOR UPDATE OF od2;
    IF NOT FOUND THEN
      RETURN "print-farm"._pf_harvest_fail('NOT_FOUND', 'Odette non trovata', 404, false);
    END IF;
    IF v_acc > 0 THEN
      IF od.status = 'FULL' THEN
        RETURN "print-farm"._pf_harvest_fail('ODETTE_FULL',
          format('Odette %s è già segnata come PIENA: scegli un''altra odette o riportala in uso.', od.code), 409, false);
      END IF;
      SELECT coalesce(sum(quantity), 0)::int INTO v_odette_qty FROM inventory."OdetteContent" WHERE "odetteId" = v_odette_id;
      IF od."maxPieces" IS NOT NULL AND v_odette_qty + v_acc > od."maxPieces" THEN
        RETURN "print-farm"._pf_harvest_fail('ODETTE_CAPACITY',
          format('Odette %s: %s pezzi superano la capienza (%s/%s). Scegli un''altra odette.', od.code, v_acc, v_odette_qty, od."maxPieces"),
          409, false);
      END IF;
    END IF;
    -- D-03: si sposta solo con pezzi buoni o «segna piena».
    IF v_to_location IS NOT NULL AND (v_acc > 0 OR v_mark_full)
       AND v_to_location IS DISTINCT FROM od."locationId" THEN
      IF NOT EXISTS (SELECT 1 FROM inventory."WarehouseLocation" WHERE id = v_to_location) THEN
        RETURN "print-farm"._pf_harvest_fail('NOT_FOUND', 'Posizione di destinazione non trovata', 404, false);
      END IF;
      IF jsonb_typeof(v_move->'expectedOccupantIds') = 'array' THEN
        PERFORM pg_advisory_xact_lock(hashtext('location'), hashtext(v_to_location::text));
        SELECT coalesce(array_agg(id ORDER BY id), ARRAY[]::uuid[]) INTO v_occupants
        FROM inventory."Odette"
        WHERE "locationId" = v_to_location AND status::text <> 'OUT_OF_SERVICE' AND id <> v_odette_id;
        SELECT coalesce(array_agg(x::uuid ORDER BY x::uuid), ARRAY[]::uuid[]) INTO v_expected_occupants
        FROM jsonb_array_elements_text(v_move->'expectedOccupantIds') AS e(x)
        WHERE x::uuid <> v_odette_id;
        IF v_occupants IS DISTINCT FROM v_expected_occupants THEN
          RETURN "print-farm"._pf_harvest_fail('LOCATION_TAKEN',
            'La posizione scelta è cambiata nel frattempo: ricalcolo la destinazione.', 409, true);
        END IF;
      END IF;
      v_moved := true;
    END IF;
  END IF;

  -- Bobina della run per la catena ISO: senza lotto materiale serve la riparazione in TypeScript.
  IF r.id IS NOT NULL THEN
    v_iso_spool := coalesce(v_confirmed_spool, r."spoolId", pr."currentSpoolId",
      -- R-182: il ripiego salta gli slot fuori uso, la bobina lì è in deposito.
      -- Stessa regola di resolveIsoSpoolId (lib/harvest/rpc/plan.ts): AMS-HT = 128..253.
      (SELECT s."spoolId" FROM "print-farm"."PrinterAmsSlot" s
       LEFT JOIN "print-farm"."PrinterAmsUnit" oos_u ON oos_u.id = s."amsUnitId"
       JOIN "print-farm"."Printer" oos_p ON oos_p.id = s."printerId"
       WHERE s."printerId" = v_printer_id AND s."spoolId" IS NOT NULL
         AND NOT (CASE
           WHEN s."amsUnit" >= 128 OR oos_u."amsModel"::text = 'AMS_HT' THEN EXISTS (
             SELECT 1 FROM unnest(coalesce(oos_p."outOfServiceAmsSlots", ARRAY[]::integer[])) AS oos_c(code)
             WHERE oos_c.code BETWEEN 128 AND 253)
           ELSE (s."amsUnit" * 4 + s.slot) = ANY (coalesce(oos_p."outOfServiceAmsSlots", ARRAY[]::integer[]))
         END)
       ORDER BY s."amsUnit", s.slot LIMIT 1));
    IF v_iso_spool IS NOT NULL THEN
      SELECT "inventoryLotId" INTO v_iso_spool_lot FROM "print-farm"."FilamentSpool" WHERE id = v_iso_spool;
      IF FOUND AND v_iso_spool_lot IS NULL THEN
        RETURN "print-farm"._pf_harvest_fail('NEEDS_REPAIR', 'Bobina senza lotto materiale', 409, true)
          || jsonb_build_object('repair', 'spool_lot', 'spoolId', v_iso_spool);
      END IF;
    END IF;
  END IF;

  -- coalesce: senza override `NULL IN (…)` è NULL e NOT v_blocked non sarebbe mai vero.
  v_blocked := v_set_maint OR coalesce(pr.override, '') IN ('MAINTENANCE', 'DISABLED')
    OR v_mark_unloaded;  -- D-09: nessuna ristampa automatica

  -- ===================== FASE B: scritture =====================
  IF v_align_parts OR v_align_payload THEN
    UPDATE "print-farm"."PrinterAssignment"
    SET "partsExpected" = CASE WHEN v_align_parts THEN v_new_parts_expected ELSE "partsExpected" END,
        "startPayload" = CASE WHEN v_align_payload THEN v_new_payload ELSE "startPayload" END,
        "updatedAt" = now()
    WHERE id = v_assignment_id;
    v_effects := v_effects || jsonb_build_object('aligned', jsonb_build_object(
      'partsExpected', CASE WHEN v_align_parts THEN v_new_parts_expected END, 'payload', v_align_payload));
  END IF;
  IF v_link_needed THEN
    UPDATE "print-farm"."PrinterAssignment" SET "productionJobId" = v_job_id, "updatedAt" = now()
    WHERE id = v_assignment_id;
    v_effects := v_effects || jsonb_build_object('linkedProductionJobId', v_job_id);
  END IF;

  -- Catena ISO: job → lotto di produzione (fratello dello stesso ordine o nuovo).
  IF v_job_id IS NOT NULL THEN
    v_lot_id := j."productionLotId";
    IF v_lot_id IS NULL THEN
      IF j."productOrderId" IS NOT NULL THEN
        SELECT "productionLotId" INTO v_lot_id FROM "print-farm"."ProductionJob"
        WHERE "productOrderId" = j."productOrderId" AND "productionLotId" IS NOT NULL AND id <> j.id
        ORDER BY "createdAt" ASC LIMIT 1;
      END IF;
      IF v_lot_id IS NULL THEN
        INSERT INTO inventory."ProductionLot" (id, code, note, "updatedAt")
        VALUES (gen_random_uuid(),
                'LOT-' || to_char(now(), 'YYYY-MM') || '-' || upper(to_hex((extract(epoch FROM clock_timestamp()) * 1000)::bigint)),
                format('Auto-creato in harvest per assignment %s', v_assignment_id), now())
        RETURNING id INTO v_lot_id;
        v_effects := v_effects || jsonb_build_object('productionLotCreated', v_lot_id);
      END IF;
      UPDATE "print-farm"."ProductionJob" SET "productionLotId" = v_lot_id, "updatedAt" = now() WHERE id = v_job_id;
    END IF;
  END IF;

  -- Catena ISO sulla run: stampante, job, bobina (la bobina confermata vince).
  IF r.id IS NOT NULL THEN
    UPDATE "print-farm"."PrintRun"
    SET "printerId" = coalesce("printerId", v_printer_id),
        "productionJobId" = coalesce("productionJobId", v_job_id),
        "spoolId" = CASE WHEN v_confirmed_spool IS NOT NULL THEN v_confirmed_spool ELSE coalesce("spoolId", v_iso_spool) END,
        "updatedAt" = now()
    WHERE id = r.id
      AND ("printerId" IS NULL OR ("productionJobId" IS NULL AND v_job_id IS NOT NULL)
           OR ("spoolId" IS NULL AND v_iso_spool IS NOT NULL)
           OR (v_confirmed_spool IS NOT NULL AND "spoolId" IS DISTINCT FROM v_confirmed_spool));
  END IF;

  IF v_part_id IS NOT NULL AND v_remaining > 0 AND v_acc > 0 THEN
    SELECT lot_id, created INTO v_inv_lot, v_inv_lot_created
    FROM "print-farm"._pf_harvest_inventory_lot(v_part_id, v_lot_id, v_order_id, v_expected);
    IF v_inv_lot_created THEN
      v_effects := v_effects || jsonb_build_object('inventoryLotCreated', v_inv_lot);
    END IF;
  END IF;
  IF v_acc > 0 AND v_tracked AND v_inv_lot IS NULL THEN
    RAISE EXCEPTION 'inventoryLotId mancante, impossibile completare lo scarico tracciato' USING ERRCODE = 'PF500';
  END IF;

  -- Fotografie prima degli incrementi (righe già bloccate).
  v_job_before_printed := coalesce(j."quantityPrinted", 0);
  v_job_before_failed := coalesce(j."quantityFailed", 0);
  IF v_order_id IS NOT NULL AND v_part_id IS NOT NULL AND v_acc > 0 THEN
    SELECT coalesce("quantityProduced", 0) INTO v_orderpart_before
    FROM inventory."ProductOrderProductPart"
    WHERE "productOrderId" = v_order_id AND "productPartId" = v_part_id;
    v_orderpart_before := coalesce(v_orderpart_before, 0);
  END IF;

  -- Scarico.
  v_text := coalesce(v_notes, CASE
    WHEN v_mark_unloaded AND v_job_id IS NULL AND v_acc > 0 THEN 'Scaricato con registrazione inventario standalone'
    WHEN v_mark_unloaded THEN 'Scaricato senza conteggio (manuale)'
    WHEN p_source = 'DETAIL' THEN ''
    ELSE format('Scarico bulk progressivo - %s OK, %s scarti', v_acc, v_rej) END);
  IF v_write_harvest THEN  -- D-09
    INSERT INTO "print-farm"."PrinterHarvest" (
      id, "assignmentId", "printerId", "printRunId", "odetteId", "harvestedByUserId", "harvestedAt",
      "partsAccepted", "partsRejected", "partsTotal", "assignmentStatusAtHarvest", "rejectReason",
      notes, "productionLotId", "idempotencyKey", "updatedAt"
    ) VALUES (
      gen_random_uuid(), v_assignment_id, v_printer_id, r.id, v_odette_id, p_operator_id, now(),
      v_acc, v_rej, v_acc + v_rej, v_status,
      CASE WHEN v_rej > 0 THEN v_reject_reason END,
      CASE WHEN v_key IS NOT NULL
           THEN '{"idempotencyKey":' || to_json(v_key)::text || ',"text":' || to_json(v_text)::text || '}'
           ELSE nullif(v_text, '') END,
      v_lot_id, v_key, now()
    ) RETURNING id INTO v_harvest_id;
  END IF;

  -- Odetta: contenuto, stato, spostamento.
  IF v_odette_id IS NOT NULL THEN
    IF v_acc > 0 THEN
      SELECT id INTO v_content_id FROM inventory."OdetteContent"
      WHERE "odetteId" = v_odette_id AND "PartId" IS NOT DISTINCT FROM v_part_id
        AND "inventoryLotId" IS NOT DISTINCT FROM v_inv_lot AND "productOrderId" IS NOT DISTINCT FROM v_order_id
      LIMIT 1;
      IF v_content_id IS NOT NULL THEN
        UPDATE inventory."OdetteContent"
        SET quantity = quantity + v_acc, "assignmentId" = v_assignment_id, "productOrderId" = v_order_id, "updatedAt" = now()
        WHERE id = v_content_id;
      ELSE
        SELECT id INTO v_content_id FROM inventory."OdetteContent"
        WHERE "odetteId" = v_odette_id AND "PartId" IS NOT DISTINCT FROM v_part_id
          AND (v_lot_id IS NULL OR "lotId" = v_lot_id) AND "inventoryLotId" IS NULL
        LIMIT 1;
        IF v_content_id IS NOT NULL THEN
          UPDATE inventory."OdetteContent"
          SET quantity = quantity + v_acc, "lotId" = v_lot_id, "inventoryLotId" = v_inv_lot,
              "productOrderId" = v_order_id, "assignmentId" = v_assignment_id, "updatedAt" = now()
          WHERE id = v_content_id;
        ELSE
          INSERT INTO inventory."OdetteContent" (id, "odetteId", "PartId", quantity, "lotId", "inventoryLotId", "productOrderId", "assignmentId", "updatedAt")
          VALUES (gen_random_uuid(), v_odette_id, v_part_id, v_acc, v_lot_id, v_inv_lot, v_order_id, v_assignment_id, now())
          RETURNING id INTO v_content_id;
        END IF;
      END IF;
    END IF;

    SELECT coalesce(sum(quantity), 0)::int INTO v_odette_qty FROM inventory."OdetteContent" WHERE "odetteId" = v_odette_id;
    IF v_mark_full OR (od."maxPieces" IS NOT NULL AND v_odette_qty >= od."maxPieces") THEN
      v_fill_id := "print-farm"._pf_harvest_mark_odette_full(v_odette_id, p_operator_id,
                     CASE WHEN v_mark_full THEN 'HARVEST' ELSE 'CAPACITY' END);
      v_effects := v_effects || jsonb_build_object('odetteMarkedFull', jsonb_build_object(
        'odetteId', v_odette_id, 'fillHistoryId', v_fill_id, 'previousStatus', od.status));
    ELSIF v_acc > 0 AND od.status IN ('EMPTY', 'RESERVED') THEN
      UPDATE inventory."Odette" SET status = 'IN_USE', "lockedStage" = 'RAW', "updatedAt" = now()
      WHERE id = v_odette_id;
    END IF;

    IF v_moved THEN
      v_from_location := od."locationId";
      UPDATE inventory."Odette" SET "locationId" = v_to_location, "updatedAt" = now() WHERE id = v_odette_id;
      INSERT INTO inventory."OdetteMove" (id, "odetteId", "fromLocationId", "toLocationId", "movedByUser", note)
      VALUES (gen_random_uuid(), v_odette_id, v_from_location, v_to_location, p_operator_id,
        v_note_prefix || ' - ' || CASE v_move->>'reason'
          WHEN 'stacked' THEN 'impilata su odette stessa categoria'
          WHEN 'beside' THEN 'accanto a odette dello stesso tipo'
          WHEN 'nearest_empty' THEN 'location vuota più vicina'
          ELSE 'destinazione scelta operatore' END)
      RETURNING id INTO v_move_id;
      v_effects := v_effects || jsonb_build_object('odetteMove', jsonb_build_object(
        'moveId', v_move_id, 'odetteId', v_odette_id, 'from', v_from_location, 'to', v_to_location));
    END IF;
  END IF;

  -- Contatori di assignment e run.
  IF v_remaining > 0 THEN
    UPDATE "print-farm"."PrinterAssignment"
    SET "partsProduced" = "partsProduced" + v_acc, "partsRejected" = "partsRejected" + v_rej, "updatedAt" = now()
    WHERE id = v_assignment_id;
    IF r.id IS NOT NULL THEN
      UPDATE "print-farm"."PrintRun"
      SET "quantitySuccess" = "quantitySuccess" + v_acc, "quantityFailed" = "quantityFailed" + v_rej, "updatedAt" = now()
      WHERE id = r.id;
      v_spool_result := "print-farm"._pf_harvest_spool_reconcile(
        r.id, v_spool_plan, CASE WHEN v_acc = 0 THEN v_override END, 'harvest-reconcile');
      IF v_spool_result IS NOT NULL THEN
        v_effects := v_effects || jsonb_build_object('spool', v_spool_result);
      END IF;
    END IF;
  END IF;

  -- Completamento o ristampa del FAILED parziale.
  v_total := v_already + v_acc + v_rej;
  v_complete := v_total >= v_expected;
  v_should_complete := v_complete OR v_remaining <= 0 OR v_mark_unloaded;  -- D-09: si chiude sempre

  IF v_should_complete THEN
    -- La run scaricata è dell'assignment: filtrare per assignmentId usa l'indice (closePrintRunsOnHarvest).
    UPDATE "print-farm"."PrintRun"
    SET "finishedAt" = now(), "updatedAt" = now()
    WHERE "assignmentId" = v_assignment_id AND "finishedAt" IS NULL
      AND (id = r.id OR status = 'IN_PROGRESS');
    UPDATE "print-farm"."PrintRun"
    SET status = CASE WHEN v_status IN ('FAILED', 'START_FAILED') THEN 'FAILED' ELSE 'COMPLETED' END::"print-farm"."PrintRunStatus",
        "updatedAt" = now()
    WHERE "assignmentId" = v_assignment_id AND status = 'IN_PROGRESS';
    UPDATE "print-farm"."PrinterAssignment"
    SET status = 'COMPLETED', "completedAt" = now(), "updatedAt" = now(),
        notes = CASE WHEN v_mark_unloaded AND NOT v_has_harvest THEN v_text ELSE notes END  -- D-09
    WHERE id = v_assignment_id AND status::text <> 'COMPLETED';
  ELSIF v_job_id IS NOT NULL AND NOT v_blocked AND v_status = 'FAILED' THEN
    v_rem_after := v_parts_expected - v_total;
    IF v_rem_after > 0 THEN
      v_payload := "print-farm"._pf_harvest_start_payload(jf.id, pr.serial, v_rem_after, v_reprint);
      IF v_rej > 0 THEN
        UPDATE "print-farm"."PrinterAssignment"
        SET status = 'COMPLETED', "completedAt" = now(),
            notes = format('Bulk progressivo chiuso per scarti (%s rejected)', v_rej), "updatedAt" = now()
        WHERE id = v_assignment_id;
        INSERT INTO "print-farm"."PrinterAssignment" (
          id, "productionJobId", "printerId", status, "scheduledAt", "queuePosition", "partsExpected",
          "materialRequired", "colorRequired", "startPayload", notes, "updatedAt"
        ) VALUES (
          gen_random_uuid(), v_job_id, v_printer_id, 'SCHEDULED', now(), 0, v_rem_after,
          a."materialRequired", a."colorRequired", v_payload,
          format('Ristampa bulk progressivo post-scarti (%s pezzi)', v_rem_after), now()
        ) RETURNING id INTO v_reprint_id;
        v_reprint_action := 'created';
      ELSE
        UPDATE "print-farm"."PrinterAssignment"
        SET status = 'SCHEDULED', "scheduledAt" = now(), "queuePosition" = 0, "partsExpected" = v_rem_after,
            "partsProduced" = 0, "partsRejected" = 0,
            "startPayload" = coalesce(v_payload, "startPayload"),
            notes = format('Ristampato dopo scarico bulk progressivo parziale (%s OK)', v_acc), "updatedAt" = now()
        WHERE id = v_assignment_id;
        v_reset := true;
        v_reprint_id := v_assignment_id;
        v_reprint_action := 'reused';
      END IF;
      v_effects := v_effects || jsonb_build_object('partialReprint', jsonb_build_object(
        'action', v_reprint_action, 'assignmentId', v_reprint_id, 'parts', v_rem_after));
    END IF;
  END IF;

  IF v_set_maint THEN
    PERFORM "print-farm"._pf_harvest_set_maintenance(v_printer_id, v_maint_reason, p_operator_id,
      CASE WHEN p_source = 'DETAIL' THEN 'harvest_complete' ELSE 'harvest_bulk_single' END);
  END IF;

  -- D-01: la stampante si libera sempre (il piatto è vuoto); la manutenzione la tiene ferma.
  SELECT EXISTS (SELECT 1 FROM "print-farm"."PrinterAssignment"
                 WHERE "printerId" = v_printer_id AND status = 'QUEUED') INTO v_next_queued;
  UPDATE "print-farm"."Printer"
  SET "operationalStatus" = CASE WHEN v_next_queued THEN 'QUEUED' ELSE 'AVAILABLE' END::public.printer_operational_status,
      "hasCompletedPrintOnBed" = false, "hasCompletedPrintOnBedAt" = NULL,
      "hasCompletedPrintOnBedAssignmentId" = NULL, "updatedAt" = now()
  WHERE id = v_printer_id;

  -- Job: contatori, scarti a fine job, ristampa urgente, stato.
  IF v_job_id IS NOT NULL AND v_remaining > 0 THEN
    UPDATE "print-farm"."ProductionJob"
    SET "quantityPrinted" = "quantityPrinted" + v_acc, "quantityFailed" = "quantityFailed" + v_rej, "updatedAt" = now()
    WHERE id = v_job_id
    RETURNING quantity, "quantityPrinted" INTO v_job_after;

    IF v_rej > 0 AND NOT v_blocked THEN
      v_eoj := "print-farm"._pf_harvest_end_of_job_scraps(v_job_id, v_printer_id, v_rej,
                 v_job_after."quantityPrinted", v_job_after.quantity);
      v_eoj_applied := coalesce((v_eoj->>'applied')::boolean, false);
      IF v_eoj_applied THEN
        v_effects := v_effects || jsonb_build_object('endOfJobScraps', v_eoj);
      END IF;
    END IF;

    IF (v_status = 'FAILED' OR v_eoj_applied) AND NOT v_blocked THEN
      v_urgent := "print-farm"._pf_harvest_urgent_next(v_job_id, v_printer_id, pr.serial,
                    a."materialRequired", a."colorRequired", v_assignment_id, v_failure_streak, v_reprint);
      IF v_urgent->>'action' IN ('created', 'updated') THEN
        v_effects := v_effects || jsonb_build_object('urgentReprint', v_urgent);
      END IF;
    END IF;
  END IF;

  IF v_job_id IS NOT NULL THEN
    SELECT quantity, "quantityPrinted", status::text AS status INTO v_job_after
    FROM "print-farm"."ProductionJob" WHERE id = v_job_id;
    IF NOT v_eoj_applied AND v_job_after."quantityPrinted" >= v_job_after.quantity AND v_job_after.status <> 'FULFILLED' THEN
      UPDATE "print-farm"."ProductionJob" SET status = 'FULFILLED', "finishedAt" = now(), "updatedAt" = now() WHERE id = v_job_id;
    ELSIF NOT v_eoj_applied AND v_acc > 0 AND v_job_after.status NOT IN ('IN_PROGRESS', 'FULFILLED') THEN
      UPDATE "print-farm"."ProductionJob" SET status = 'IN_PROGRESS', "updatedAt" = now() WHERE id = v_job_id;
    END IF;
    IF v_order_id IS NOT NULL AND v_acc > 0 THEN
      PERFORM "print-farm"._pf_harvest_order_rollup(v_order_id, j."productPartId", v_acc, p_operator_id);
    END IF;
    -- FAILED senza pezzi da registrare: solo la ripianificazione.
    IF v_remaining <= 0 AND v_status = 'FAILED' AND NOT v_blocked THEN
      v_urgent := "print-farm"._pf_harvest_urgent_next(v_job_id, v_printer_id, pr.serial,
                    a."materialRequired", a."colorRequired", v_assignment_id, v_failure_streak, v_reprint);
      IF v_urgent->>'action' IN ('created', 'updated') THEN
        v_effects := v_effects || jsonb_build_object('urgentReprint', v_urgent);
      END IF;
    END IF;
  END IF;

  -- Movimento di produzione (i trigger aggiornano stock e lotto).
  IF v_part_id IS NOT NULL AND v_inv_lot IS NOT NULL AND v_remaining > 0 AND v_acc > 0 THEN
    INSERT INTO inventory."Movement" (id, "productPartId", quantity, type, date, "byUserId", "odetteId", "lotId", "productOrderId", "harvestId")
    VALUES (gen_random_uuid(), v_part_id, v_acc, 'PRODUZIONE', clock_timestamp(), p_operator_id, v_odette_id, v_inv_lot, v_order_id, v_harvest_id)
    RETURNING id INTO v_movement_id;
  END IF;

  UPDATE "print-farm"."HarvestDraft" SET state = 'CONFIRMED', "updatedAt" = now()
  WHERE "assignmentId" = v_assignment_id AND state IN ('DRAFT', 'STALE');

  IF v_harvest_id IS NOT NULL AND v_effects <> '{}'::jsonb THEN
    UPDATE "print-farm"."PrinterHarvest" SET effects = v_effects WHERE id = v_harvest_id;
  END IF;

  -- ===================== FASE C: verifica =====================
  IF EXISTS (SELECT 1 FROM "print-farm"."Printer" WHERE id = v_printer_id AND "hasCompletedPrintOnBed") THEN
    v_verify := v_verify || 'Printer hasCompletedPrintOnBed non azzerato';
  END IF;
  IF v_remaining > 0 THEN
    SELECT status::text AS status, "partsProduced", "partsRejected" INTO h
    FROM "print-farm"."PrinterAssignment" WHERE id = v_assignment_id;
    IF v_reset THEN
      IF h."partsProduced" <> 0 OR h."partsRejected" <> 0 OR h.status <> 'SCHEDULED' THEN
        v_verify := v_verify || format('Assignment %s: ristampa FAILED non coerente', v_assignment_id);
      END IF;
    ELSE
      IF h."partsProduced" - coalesce(a."partsProduced", 0) <> v_acc THEN
        v_verify := v_verify || format('Assignment %s partsProduced delta mismatch', v_assignment_id);
      END IF;
      IF h."partsRejected" - coalesce(a."partsRejected", 0) <> v_rej THEN
        v_verify := v_verify || format('Assignment %s partsRejected delta mismatch', v_assignment_id);
      END IF;
      IF v_should_complete AND h.status NOT IN ('COMPLETED', 'SCHEDULED') THEN
        v_verify := v_verify || format('Assignment %s non completato: stato %s', v_assignment_id, h.status);
      END IF;
    END IF;
    IF v_write_harvest AND NOT EXISTS (SELECT 1 FROM "print-farm"."PrinterHarvest" WHERE id = v_harvest_id
                   AND "partsAccepted" = v_acc AND "partsRejected" = v_rej) THEN
      v_verify := v_verify || 'PrinterHarvest non creato';
    END IF;
  END IF;
  IF v_job_id IS NOT NULL THEN
    SELECT quantity, "quantityPrinted", "quantityFailed", status::text AS status INTO h
    FROM "print-farm"."ProductionJob" WHERE id = v_job_id;
    IF v_remaining > 0 THEN
      IF h."quantityPrinted" - v_job_before_printed <> v_acc THEN
        v_verify := v_verify || format('ProductionJob %s quantityPrinted delta mismatch', v_job_id);
      END IF;
      IF h."quantityFailed" - v_job_before_failed <> v_rej THEN
        v_verify := v_verify || format('ProductionJob %s quantityFailed delta mismatch', v_job_id);
      END IF;
    END IF;
    IF h."quantityPrinted" >= h.quantity AND h.status <> 'FULFILLED' THEN
      v_verify := v_verify || format('ProductionJob %s status incoerente (%s/%s, %s)', v_job_id, h."quantityPrinted", h.quantity, h.status);
    END IF;
  END IF;
  IF v_part_id IS NOT NULL AND v_inv_lot IS NOT NULL AND v_remaining > 0 AND v_acc > 0
     AND NOT EXISTS (SELECT 1 FROM inventory."Movement" WHERE id = v_movement_id AND "harvestId" = v_harvest_id) THEN
    v_verify := v_verify || 'Movimento inventario PRODUZIONE non creato';
  END IF;
  IF v_orderpart_before IS NOT NULL THEN
    SELECT "quantityProduced" INTO v_cnt FROM inventory."ProductOrderProductPart"
    WHERE "productOrderId" = v_order_id AND "productPartId" = v_part_id;
    IF v_cnt IS NULL THEN
      v_verify := v_verify || format('ProductOrderProductPart non trovata (ordine %s / parte %s)', v_order_id, v_part_id);
    ELSIF v_cnt - v_orderpart_before <> v_acc THEN
      v_verify := v_verify || format('ProductOrderProductPart quantityProduced delta mismatch (ordine %s)', v_order_id);
    END IF;
  END IF;
  IF v_odette_id IS NOT NULL AND v_acc > 0
     AND EXISTS (SELECT 1 FROM inventory."Odette" WHERE id = v_odette_id AND status::text = 'EMPTY') THEN
    v_verify := v_verify || format('Odette %s ancora EMPTY dopo scarico di %s pezzi', v_odette_id, v_acc);
  END IF;

  IF array_length(v_verify, 1) > 0 THEN
    RAISE EXCEPTION 'Verifica post-scarico fallita: %', array_to_string(v_verify, '; ') USING ERRCODE = 'PF500';
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'harvestId', v_harvest_id,
    'partsAccepted', v_acc,
    'partsRejected', v_rej,
    'clamped', v_clamped,
    'isComplete', v_should_complete,
    'idempotencyHit', false,
    'endOfJobScrapsApplied', v_eoj_applied,
    'reprintAssignmentId', coalesce(v_reprint_id, nullif(v_urgent->>'assignmentId', '')::uuid),
    'effects', v_effects
  );
END;
$$;
