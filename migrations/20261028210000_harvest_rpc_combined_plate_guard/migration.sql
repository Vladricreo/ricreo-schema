-- ============================================================================
-- Scarico veloce (pf_harvest_*): guardia sui piatti combinati (S-188, A-160)
--
-- Un piatto combinato (assignment con righe "PrinterAssignmentPart") si scarica
-- per parte: lotto, odetta dell'ordine, contatori di ogni job e riga parte,
-- ristampa delle sole parti scartate (R-124, client
-- `app/api/harvest/_utils/combined-harvest.ts`). La RPC conta solo il job
-- principale dell'assignment: su un combinato scriverebbe i pezzi di tutte le
-- parti su una parte sola. Quindi:
--   - pf_harvest_context: ogni assignment porta `combinedPlate` (true se ha righe
--     parte), così il piano lato TS lo rifiuta prima di scrivere;
--   - pf_harvest_apply: rifiuta la riga con `COMBINED_PLATE` (409, non
--     ritentabile) prima di chiamare _pf_harvest_apply_item, anche se il
--     chiamante non ha controllato. Si rifiuta anche con una sola riga parte
--     (es. ristampa delle sole parti scartate): i contatori della riga li
--     aggiorna solo lo scarico normale.
-- Il tablet, con la RPC accesa, deve mandare i combinati al flusso normale
-- (POST /api/harvest/bulk-single e /api/harvest/[printerId]).
--
-- Solo CREATE OR REPLACE delle due funzioni pubbliche: corpo identico a
-- 20261027090000_harvest_rpc_functions salvo le righe marcate «A-160».
-- Permessi e REVOKE restano quelli della funzione esistente.
-- ============================================================================

CREATE OR REPLACE FUNCTION "print-farm".pf_harvest_apply(p jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = ''
SET lock_timeout = '5s'
AS $$
DECLARE
  v_operator int;
  v_source text;
  v_item jsonb;
  v_result jsonb;
  v_results jsonb := '[]'::jsonb;
  v_state text;
  v_msg text;
  v_full uuid;
  v_full_errors jsonb := '[]'::jsonb;
BEGIN
  IF p IS NULL OR jsonb_typeof(p) <> 'object' OR coalesce((p->>'v')::int, 0) <> 1 THEN
    RETURN jsonb_build_object('v', 1, 'error', 'INVALID', 'message', 'Piano non valido (serve v = 1)');
  END IF;
  v_operator := CASE WHEN (p->>'operatorId') ~ '^[0-9]+$' THEN (p->>'operatorId')::int END;
  IF v_operator IS NULL OR NOT EXISTS (SELECT 1 FROM public."User" WHERE id = v_operator) THEN
    RETURN jsonb_build_object('v', 1, 'error', 'OPERATOR', 'message', 'Operatore non identificato');
  END IF;
  v_source := upper(coalesce(nullif(p->>'source', ''), 'BULK'));
  IF v_source NOT IN ('BULK', 'DETAIL', 'VOICE') THEN
    RETURN jsonb_build_object('v', 1, 'error', 'INVALID', 'message', 'source non valida: ' || v_source);
  END IF;
  IF jsonb_typeof(p->'items') <> 'array' OR jsonb_array_length(p->'items') = 0 THEN
    RETURN jsonb_build_object('v', 1, 'error', 'INVALID', 'message', 'items vuoto');
  END IF;
  IF jsonb_array_length(p->'items') > 50 THEN
    RETURN jsonb_build_object('v', 1, 'error', 'INVALID', 'message', 'Troppe righe in un giro (max 50)');
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p->'items') LOOP
    BEGIN
      -- A-160: un piatto combinato si scarica per parte, solo dal flusso normale.
      IF EXISTS (
        SELECT 1 FROM "print-farm"."PrinterAssignmentPart" pap
        WHERE pap."assignmentId" = nullif(v_item->>'assignmentId', '')::uuid
      ) THEN
        v_result := "print-farm"._pf_harvest_fail(
          'COMBINED_PLATE',
          'Piatto combinato: lo scarico veloce non lo gestisce, va scaricato con i conteggi per parte (scarico normale).',
          409, false);
      ELSE
        v_result := "print-farm"._pf_harvest_apply_item(v_item, v_operator, v_source);
      END IF;
      IF NOT coalesce((v_result->>'ok')::boolean, false) THEN
        -- Conflitto atteso: si annulla tutto ciò che la riga ha toccato.
        RAISE EXCEPTION USING ERRCODE = 'PF409', MESSAGE = v_result::text;
      END IF;
    EXCEPTION
      WHEN SQLSTATE 'PF409' THEN
        v_result := SQLERRM::jsonb;
      WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
        v_result := CASE
          WHEN v_state = 'PF500' THEN "print-farm"._pf_harvest_fail('VERIFY_FAILED', v_msg, 500, true)
          WHEN v_state = '55P03' THEN "print-farm"._pf_harvest_fail('LOCK_TIMEOUT', 'Stampante occupata da un''altra operazione: riprova.', 503, true)
          WHEN v_state = '40P01' THEN "print-farm"._pf_harvest_fail('DEADLOCK', 'Conflitto con un''altra operazione: riprova.', 503, true)
          WHEN v_state = '40001' THEN "print-farm"._pf_harvest_fail('SERIALIZATION', 'Conflitto con un''altra operazione: riprova.', 503, true)
          WHEN v_state = '23505' THEN "print-farm"._pf_harvest_fail('DUPLICATE', 'Scarico già in registrazione: riprova.', 409, true)
          WHEN v_state = '23514' THEN "print-farm"._pf_harvest_fail('INVARIANT', v_msg, 500, false)
          WHEN v_state IN ('22P02', '22007', '22008', '22003') THEN "print-farm"._pf_harvest_fail('INVALID', v_msg, 400, false)
          ELSE "print-farm"._pf_harvest_fail('INTERNAL', v_msg, 500, false) || jsonb_build_object('sqlstate', v_state)
        END;
    END;
    v_results := v_results || jsonb_build_array(
      jsonb_build_object('printerId', v_item->>'printerId', 'assignmentId', v_item->>'assignmentId') || v_result);
  END LOOP;

  -- Odette segnate piene senza pezzi in questo giro (oggi: solo sull'ultima stampante).
  IF jsonb_typeof(p->'additionalFullOdetteIds') = 'array' THEN
    FOR v_full IN SELECT DISTINCT x::uuid FROM jsonb_array_elements_text(p->'additionalFullOdetteIds') AS e(x) LOOP
      BEGIN
        PERFORM pg_advisory_xact_lock(hashtext('odette'), hashtext(v_full::text));
        PERFORM "print-farm"._pf_harvest_mark_odette_full(v_full, v_operator, 'HARVEST');
      EXCEPTION WHEN OTHERS THEN
        v_full_errors := v_full_errors || jsonb_build_array(jsonb_build_object('odetteId', v_full, 'message', SQLERRM));
      END;
    END LOOP;
  END IF;

  RETURN jsonb_build_object('v', 1, 'items', v_results, 'additionalFullErrors', v_full_errors);
END;
$$;

COMMENT ON FUNCTION "print-farm".pf_harvest_apply(jsonb) IS
  'Giro di scarico in una istruzione (docs/harvest-rpc-progetto.md §5-§7). Una sotto-transazione per riga; conflitti come esito ok:false.';

-- ---------------------------------------------------------------------------
-- Contesto di lettura per il piano (§19.2): solo le stampanti del giro.
-- p_options: { odetteIds: [], locationIds: [] }

-- ---------------------------------------------------------------------------
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

COMMENT ON FUNCTION "print-farm".pf_harvest_context(uuid[], jsonb) IS
  'Lettura limitata alle stampanti del giro per il piano dello scarico (docs/harvest-rpc-progetto.md §19.2).';

