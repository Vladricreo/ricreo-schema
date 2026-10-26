-- ============================================================================
-- Scarico in una sola chiamata al DB: funzioni (passi 3 e 4 del progetto)
-- Progetto: docs/harvest-rpc-progetto.md (§3-§7, §19.2), decisioni R-90.
--
--   pf_harvest_context(printerIds, options)  sola lettura, una query per il giro
--   pf_harvest_apply(plan)                   scrittura, una istruzione per il giro
--
-- Nessuna route le chiama ancora: le userà il passo 6, dietro l'interruttore
-- «Scarico veloce» (Impostazioni → Generali, riga Settings `harvest_rpc`).
--
-- Regole di scrittura (§6):
--   - fase A: lock in ordine fisso e controlli, NESSUNA scrittura;
--   - fase B: scritture, sempre con "updatedAt" esplicito (Prisma lo scrive dal
--     client, il DB non ha trigger: senza, il token ottimistico non cambierebbe);
--   - fase C: verifica dei delta letti sotto lock; se non tornano RAISE PF500.
-- Ordine dei lock (uguale al backend e a pf_swap_conclude):
--   advisory(printerId) → assignment → run → metriche → job → ordine →
--   advisory+riga odetta → advisory posizione → bobine (per id).
-- Un conflitto atteso torna come esito `ok: false` e la riga si annulla
-- (sotto-transazione); le righe del giro sono indipendenti.
--
-- Replica il percorso di oggi di POST /api/harvest/bulk-single (95% degli
-- scarichi) con le regole decise per D-01…D-08:
--   D-01 flag del piatto spento anche con «Richiedi manutenzione»;
--   D-02 reservedLotId dell'odetta mai scritto allo scarico;
--   D-03 odetta spostata solo con pezzi buoni o «segna piena»;
--   D-04 ristampa del FAILED parziale con mappa AMS e oggetti saltati;
--   D-05 ripianificazione solo sulla stessa stampante;
--   D-06 motivo scarto vuoto se l'operatore non lo sceglie;
--   D-07 assignment da scaricare scelto dal tablet, controllato contro il piatto;
--   D-08 note dell'operatore salvate anche dal bulk.
-- La modalità MARK_UNLOADED (D-09) arriva con il passo 5, insieme a Salta.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Esito di conflitto (nessuna scrittura)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "print-farm"._pf_harvest_fail(
  p_code text, p_message text, p_http int, p_retryable boolean
) RETURNS jsonb
LANGUAGE sql IMMUTABLE
SET search_path = ''
AS $$
  SELECT jsonb_build_object('ok', false, 'code', p_code, 'message', p_message,
                            'http', p_http, 'retryable', p_retryable);
$$;

-- ---------------------------------------------------------------------------
-- Payload di Start Print per una ristampa (D-04)
-- File = ultimo file del job (letto qui). Dal piano arrivano solo useAms,
-- amsMapping e materialTargets, e valgono solo se il piano era sullo stesso file.
-- skipObjects: gli oggetti attivi del piatto oltre i primi `p_parts`.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "print-farm"._pf_harvest_start_payload(
  p_file_id uuid, p_serial text, p_parts int, p_template jsonb
) RETURNS jsonb
LANGUAGE plpgsql STABLE
SET search_path = ''
AS $$
DECLARE
  f record;
  v_filename text;
  v_active int[];
  v_skip int[];
  v_template_ok boolean;
  v_options jsonb;
  v_payload jsonb;
BEGIN
  IF p_serial IS NULL OR p_file_id IS NULL THEN
    RETURN NULL;
  END IF;
  SELECT id, filename, "plateNumber", "sliceObjects" INTO f
  FROM "print-farm"."ProjectThreeMFFile" WHERE id = p_file_id;
  IF NOT FOUND OR f.filename IS NULL THEN
    RETURN NULL;
  END IF;

  v_filename := CASE
    WHEN f.filename LIKE '%.gcode.3mf' THEN f.filename
    WHEN f.filename LIKE '%.3mf' THEN regexp_replace(f.filename, '\.3mf', '.gcode.3mf')
    ELSE f.filename || '.gcode.3mf'
  END;

  -- Oggetti attivi nell'ordine del file (computeSkipObjectsFromSliceObjects).
  IF jsonb_typeof(f."sliceObjects") = 'array' THEN
    SELECT array_agg((o->>'identifyId')::numeric::int ORDER BY ord)
    INTO v_active
    FROM jsonb_array_elements(f."sliceObjects") WITH ORDINALITY AS e(o, ord)
    WHERE (o->>'identifyId') ~ '^-?[0-9]+(\.[0-9]+)?$'
      AND coalesce(o->>'skipped', 'false') IN ('false', '0', '', 'null');
  END IF;
  IF v_active IS NOT NULL AND array_length(v_active, 1) > 1
     AND p_parts > 0 AND p_parts < array_length(v_active, 1) THEN
    v_skip := v_active[p_parts + 1 : array_length(v_active, 1)];
  END IF;

  v_template_ok := p_template IS NOT NULL
    AND jsonb_typeof(p_template) = 'object'
    AND (p_template->>'fileId') = f.id::text;

  v_options := jsonb_build_object('timelapse', false, 'flowCalibration', true);
  IF v_skip IS NOT NULL AND array_length(v_skip, 1) > 0 THEN
    v_options := v_options || jsonb_build_object('skipObjects', to_jsonb(v_skip));
  END IF;

  v_payload := jsonb_build_object(
    'version', 1,
    'printerSerial', p_serial,
    'fileId', f.id,
    'filenameToPrint', v_filename,
    'plateNumber', CASE WHEN f."plateNumber" > 0 THEN f."plateNumber" ELSE 1 END,
    'useAms', CASE WHEN v_template_ok AND jsonb_typeof(p_template->'useAms') = 'boolean'
                   THEN p_template->'useAms' ELSE 'false'::jsonb END,
    'amsMapping', CASE WHEN v_template_ok AND jsonb_typeof(p_template->'amsMapping') = 'array'
                       THEN p_template->'amsMapping' ELSE '[-1,-1,-1,-1,-1]'::jsonb END,
    'options', v_options
  );
  IF v_template_ok AND jsonb_typeof(p_template->'materialTargets') = 'array'
     AND jsonb_array_length(p_template->'materialTargets') > 0 THEN
    v_payload := v_payload || jsonb_build_object('materialTargets', p_template->'materialTargets');
  END IF;
  RETURN v_payload;
END;
$$;

-- ---------------------------------------------------------------------------
-- Lotto inventario dello scarico (ensureInventoryLotForHarvest)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "print-farm"._pf_harvest_inventory_lot(
  p_part_id uuid, p_production_lot_id uuid, p_order_id uuid, p_initial int,
  OUT lot_id uuid, OUT created boolean
)
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_n bigint;
  v_code text;
  v_attempt int := 0;
BEGIN
  created := false;
  IF p_production_lot_id IS NOT NULL THEN
    SELECT id INTO lot_id FROM inventory."InventoryLot"
    WHERE "productionLotId" = p_production_lot_id AND "productPartId" = p_part_id
    LIMIT 1;
    IF lot_id IS NOT NULL THEN RETURN; END IF;
  END IF;
  IF p_order_id IS NOT NULL THEN
    SELECT id INTO lot_id FROM inventory."InventoryLot"
    WHERE "productItemOrderId" = p_order_id AND "productPartId" = p_part_id
    LIMIT 1;
    IF lot_id IS NOT NULL THEN RETURN; END IF;
  END IF;

  WHILE v_attempt < 5 LOOP
    v_attempt := v_attempt + 1;
    v_n := nextval(pg_get_serial_sequence('"inventory"."InventoryLot"', 'number'));
    v_code := 'LOT-' || extract(year FROM now())::int || '-' || lpad(v_n::text, 5, '0');
    INSERT INTO inventory."InventoryLot" (
      id, number, code, "originType", "initialQuantity", status,
      "productPartId", "productItemOrderId", "productionLotId", "manufacturedAt"
    ) VALUES (
      gen_random_uuid(), v_n, v_code, 'PRODUCTION', greatest(0, coalesce(p_initial, 0)), 'OPEN',
      p_part_id, p_order_id, p_production_lot_id, now()
    )
    ON CONFLICT (code) DO NOTHING
    RETURNING id INTO lot_id;
    IF lot_id IS NOT NULL THEN
      created := true;
      RETURN;
    END IF;
  END LOOP;
  RAISE EXCEPTION 'Impossibile creare InventoryLot: troppi conflitti di codice' USING ERRCODE = 'PF500';
END;
$$;

-- ---------------------------------------------------------------------------
-- Odetta piena + storico di riempimento (markOdettesFullWithHistory)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "print-farm"._pf_harvest_mark_odette_full(
  p_odette_id uuid, p_user_id int, p_source text
) RETURNS uuid
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  o record;
  v_pieces int;
  v_part_id uuid;
  v_part_name text;
  v_latest uuid;
  v_id uuid;
BEGIN
  SELECT od.id, od.code, od.status::text AS status, od."typeId",
         t.name AS type_name, t."categoryId", c.name AS category_name
  INTO o
  FROM inventory."Odette" od
  LEFT JOIN inventory."OdetteType" t ON t.id = od."typeId"
  LEFT JOIN inventory."Category" c ON c.id = t."categoryId"
  WHERE od.id = p_odette_id;
  IF NOT FOUND THEN RETURN NULL; END IF;

  SELECT coalesce(sum(quantity), 0)::int INTO v_pieces
  FROM inventory."OdetteContent" WHERE "odetteId" = p_odette_id;

  SELECT oc."PartId", pp.name INTO v_part_id, v_part_name
  FROM inventory."OdetteContent" oc
  LEFT JOIN inventory."ProductPart" pp ON pp.id = oc."PartId"
  WHERE oc."odetteId" = p_odette_id AND oc."PartId" IS NOT NULL AND oc.quantity > 0
  ORDER BY oc.quantity DESC, oc."createdAt", oc.id
  LIMIT 1;

  IF o.status <> 'FULL' THEN
    UPDATE inventory."Odette"
    SET status = 'FULL', "lockedStage" = 'RAW', "updatedAt" = now()
    WHERE id = p_odette_id;
  END IF;

  SELECT id INTO v_latest FROM inventory."OdetteFillHistory"
  WHERE "odetteId" = p_odette_id ORDER BY "markedFullAt" DESC LIMIT 1;

  IF o.status = 'FULL' AND v_latest IS NOT NULL THEN
    UPDATE inventory."OdetteFillHistory"
    SET "odetteCode" = o.code, "odetteTypeId" = o."typeId", "odetteTypeName" = o.type_name,
        "categoryId" = o."categoryId", "categoryName" = o.category_name,
        "pieceCount" = v_pieces, "partId" = v_part_id, "partName" = v_part_name,
        "markedFullAt" = now(), "markedFullByUserId" = p_user_id, source = p_source
    WHERE id = v_latest;
    RETURN v_latest;
  END IF;

  INSERT INTO inventory."OdetteFillHistory" (
    id, "odetteId", "odetteCode", "odetteTypeId", "odetteTypeName", "categoryId", "categoryName",
    "pieceCount", "partId", "partName", "markedFullAt", "markedFullByUserId", source
  ) VALUES (
    gen_random_uuid(), p_odette_id, o.code, o."typeId", o.type_name, o."categoryId", o.category_name,
    v_pieces, v_part_id, v_part_name, now(), p_user_id, p_source
  ) RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- Avanzamento dell'ordine (updateProductOrderAfterHarvest), ordine già bloccato
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "print-farm"._pf_harvest_order_rollup(
  p_order_id uuid, p_part_id uuid, p_delta int, p_user_id int
) RETURNS void
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  o record;
  v_updated int;
  v_any_produced boolean;
  v_all_complete boolean;
  v_min_progress numeric;
  v_target int;
  v_next int;
BEGIN
  IF p_order_id IS NULL THEN RETURN; END IF;
  IF p_delta > 0 AND p_part_id IS NULL THEN
    RAISE EXCEPTION 'Aggiornamento ProductOrder impossibile: productPartId mancante' USING ERRCODE = 'PF500';
  END IF;

  IF p_delta <> 0 AND p_part_id IS NOT NULL THEN
    UPDATE inventory."ProductOrderProductPart"
    SET "quantityProduced" = "quantityProduced" + p_delta
    WHERE "productOrderId" = p_order_id AND "productPartId" = p_part_id;
    GET DIAGNOSTICS v_updated = ROW_COUNT;
    IF v_updated = 0 THEN
      RAISE EXCEPTION 'Aggiornamento ProductOrder impossibile: nessuna riga per ordine % e parte %',
        p_order_id, p_part_id USING ERRCODE = 'PF500';
    END IF;
  END IF;

  SELECT id, "quantityToProduce", "productionStatus"::text AS status INTO o
  FROM inventory."ProductOrder" WHERE id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ProductOrder % non trovato durante lo scarico', p_order_id USING ERRCODE = 'PF500';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM inventory."ProductOrderProductPart" WHERE "productOrderId" = p_order_id) THEN
    RAISE EXCEPTION 'ProductOrder % senza righe parte', p_order_id USING ERRCODE = 'PF500';
  END IF;

  SELECT
    bool_or(greatest(0, "quantityProduced") > 0),
    bool_and(greatest(0, quantity) <= 0 OR greatest(0, "quantityProduced") >= greatest(0, quantity)),
    min(CASE WHEN greatest(0, quantity) <= 0 THEN 1
             ELSE least(1, greatest(0, "quantityProduced")::numeric / greatest(0, quantity)) END)
  INTO v_any_produced, v_all_complete, v_min_progress
  FROM inventory."ProductOrderProductPart" WHERE "productOrderId" = p_order_id;

  v_target := greatest(0, coalesce(o."quantityToProduce", 0));
  IF v_target > 0 THEN
    v_next := CASE WHEN v_all_complete THEN v_target ELSE floor(v_min_progress * v_target)::int END;
  ELSE
    v_next := CASE WHEN v_all_complete THEN 1 ELSE 0 END;
  END IF;

  UPDATE inventory."ProductOrder"
  SET "quantityProduced" = v_next, "updatedAt" = now()
  WHERE id = p_order_id;

  IF v_all_complete AND o.status <> 'PRODUCED' THEN
    UPDATE inventory."ProductOrder"
    SET "productionStatus" = 'PRODUCED', "producedByUserId" = p_user_id, "finishedAt" = now(), "updatedAt" = now()
    WHERE id = p_order_id;
  ELSIF NOT v_all_complete AND v_any_produced AND o.status = 'PRODUCED' THEN
    UPDATE inventory."ProductOrder"
    SET "productionStatus" = 'PRODUCING', "finishedAt" = NULL, "updatedAt" = now()
    WHERE id = p_order_id;
  ELSIF NOT v_all_complete AND v_any_produced AND o.status = 'READY_TO_PRODUCE' THEN
    UPDATE inventory."ProductOrder"
    SET "productionStatus" = 'PRODUCING', "updatedAt" = now()
    WHERE id = p_order_id;
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- Consumo bobina (reconcileSpoolConsumption): formula invariata.
-- p_plan dal TypeScript: { totalWeight, entries: [{spoolId, share}], primarySpoolId }
--   entries = un elemento per materiale del file (quota = peso del materiale /
--   totale), già risolto sulla bobina montata; senza materiali, primarySpoolId.
-- Run e metriche sono già bloccate dal chiamante. Ritorna i grammi per bobina.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "print-farm"._pf_harvest_spool_reconcile(
  p_run_id uuid, p_plan jsonb, p_override numeric, p_ledger_source text
) RETURNS jsonb
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  r record;
  m record;
  v_total numeric;
  v_part_count int;
  v_has_valid boolean;
  v_expected int;
  v_scale numeric;
  v_max numeric;
  v_cum int;
  v_capped int;
  v_parts_based numeric;
  v_floor numeric := 0;
  v_cp numeric;
  v_override numeric;
  v_target numeric;
  v_already numeric;
  v_delta numeric;
  v_deltas jsonb := '{}'::jsonb;
  v_entry jsonb;
  v_spool uuid;
  v_sdelta numeric;
  k text;
  v_has_entries boolean;
BEGIN
  IF p_run_id IS NULL OR p_plan IS NULL OR jsonb_typeof(p_plan) <> 'object' THEN
    RETURN NULL;
  END IF;
  v_total := nullif(p_plan->>'totalWeight', '')::numeric;
  IF v_total IS NULL OR v_total <= 0 THEN RETURN NULL; END IF;

  SELECT pr.id, pr.status::text AS status, pr."completionPercent", pr."expectedQuantity",
         pr."quantitySuccess", pr."quantityFailed", f."partCount"
  INTO r
  FROM "print-farm"."PrintRun" pr
  LEFT JOIN "print-farm"."ProjectThreeMFFile" f ON f.id = pr."fileId"
  WHERE pr.id = p_run_id;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT id, "lastSnapshotGrams", "snapshotDeductedGrams" INTO m
  FROM "print-farm"."PrintRunMetrics" WHERE "printRunId" = p_run_id;

  v_has_valid := coalesce(r."partCount", 0) > 0;
  v_part_count := CASE WHEN v_has_valid THEN r."partCount" ELSE 1 END;
  v_expected := CASE WHEN r."expectedQuantity" > 0 THEN least(r."expectedQuantity", v_part_count) END;
  v_scale := CASE WHEN v_part_count > 1 AND v_expected IS NOT NULL AND v_expected < v_part_count
                  THEN v_expected::numeric / v_part_count ELSE 1 END;
  v_max := round(v_total * v_scale, 2);

  v_cum := coalesce(r."quantitySuccess", 0) + coalesce(r."quantityFailed", 0);
  v_capped := least(v_cum, coalesce(v_expected, v_part_count));
  v_parts_based := CASE WHEN v_capped > 0 THEN least(v_total * v_capped / v_part_count, v_max) ELSE 0 END;

  v_cp := least(greatest(coalesce(r."completionPercent", 0), 0), 100);
  IF v_cp > 0 THEN v_floor := v_max * v_cp / 100; END IF;
  IF m.id IS NOT NULL AND coalesce(m."lastSnapshotGrams", 0) <> 0 THEN
    v_floor := greatest(v_floor, m."lastSnapshotGrams");
  END IF;
  v_floor := least(v_floor, v_max);

  v_override := CASE WHEN p_override IS NOT NULL THEN least(greatest(p_override, 0), 100) END;
  v_target := CASE
    WHEN v_override IS NOT NULL THEN round(v_max * v_override / 100, 2)
    WHEN r.status = 'COMPLETED' THEN round(least(greatest(v_parts_based, v_floor), v_max), 2)
    ELSE round(least(v_floor, v_max), 2)
  END;
  v_already := coalesce(m."snapshotDeductedGrams", 0);
  v_delta := round(v_target - v_already, 2);

  IF v_delta <> 0 THEN
    v_has_entries := jsonb_typeof(p_plan->'entries') = 'array' AND jsonb_array_length(p_plan->'entries') > 0;
    IF v_has_entries THEN
      FOR v_entry IN SELECT * FROM jsonb_array_elements(p_plan->'entries') LOOP
        v_spool := nullif(v_entry->>'spoolId', '')::uuid;
        v_sdelta := round(v_delta * coalesce((v_entry->>'share')::numeric, 0), 2);
        IF v_spool IS NOT NULL AND v_sdelta <> 0 THEN
          v_deltas := jsonb_set(v_deltas, ARRAY[v_spool::text],
            to_jsonb(coalesce((v_deltas->>v_spool::text)::numeric, 0) + v_sdelta));
        END IF;
      END LOOP;
    ELSE
      v_spool := nullif(p_plan->>'primarySpoolId', '')::uuid;
      IF v_spool IS NULL THEN RETURN NULL; END IF;
      v_deltas := jsonb_build_object(v_spool::text, v_delta);
    END IF;

    IF v_deltas = '{}'::jsonb THEN RETURN NULL; END IF;

    -- Bobine bloccate in ordine di id (stesso ordine del tracker del backend).
    FOR k IN SELECT key FROM jsonb_each(v_deltas) ORDER BY key LOOP
      v_sdelta := round((v_deltas->>k)::numeric, 2);
      CONTINUE WHEN v_sdelta = 0;
      PERFORM 1 FROM "print-farm"."FilamentSpool" WHERE id = k::uuid FOR UPDATE;
      IF v_sdelta > 0 THEN
        UPDATE "print-farm"."FilamentSpool"
        SET "remainingWeight" = "remainingWeight" - v_sdelta, "updatedAt" = now()
        WHERE id = k::uuid AND status::text = 'ACTIVE';
        UPDATE "print-farm"."FilamentSpool"
        SET "remainingWeight" = 0, "updatedAt" = now()
        WHERE id = k::uuid AND status::text = 'ACTIVE' AND "remainingWeight" <= 0;
      ELSE
        UPDATE "print-farm"."FilamentSpool"
        SET "remainingWeight" = "remainingWeight" + (-v_sdelta), "updatedAt" = now()
        WHERE id = k::uuid AND status::text = 'ACTIVE';
      END IF;
      INSERT INTO "print-farm"."PrintRunSpoolConsumption" (id, "printRunId", "spoolId", source, "gramsUsed", "updatedAt")
      VALUES (gen_random_uuid(), p_run_id, k::uuid, p_ledger_source, v_sdelta, now())
      ON CONFLICT ("printRunId", "spoolId", source)
      DO UPDATE SET "gramsUsed" = "print-farm"."PrintRunSpoolConsumption"."gramsUsed" + EXCLUDED."gramsUsed",
                    "updatedAt" = now();
    END LOOP;
  END IF;

  IF m.id IS NOT NULL THEN
    UPDATE "print-farm"."PrintRunMetrics"
    SET "filamentUsedGrams" = v_target, "snapshotDeductedGrams" = v_target
    WHERE id = m.id;
  ELSE
    INSERT INTO "print-farm"."PrintRunMetrics" (id, "printRunId", "filamentUsedGrams", "expectedFilamentGrams", "snapshotDeductedGrams")
    VALUES (gen_random_uuid(), p_run_id, v_target, v_total, v_target);
  END IF;

  RETURN jsonb_build_object('targetGrams', v_target, 'deltaGrams', v_delta, 'spools', v_deltas);
END;
$$;

-- ---------------------------------------------------------------------------
-- Scarti a fine job (handleEndOfJobScrapsReprint), job già bloccato
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "print-farm"._pf_harvest_end_of_job_scraps(
  p_job_id uuid, p_printer_id uuid, p_rejected int, p_printed_after int, p_quantity_before int
) RETURNS jsonb
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  j record;
  v_file_status text;
  v_would boolean;
  v_new_q int;
  v_note text;
  v_cancelled uuid[];
BEGIN
  IF p_rejected IS NULL OR p_rejected <= 0 THEN
    RETURN jsonb_build_object('applied', false, 'reason', 'no_rejects');
  END IF;
  IF p_printed_after + p_rejected < p_quantity_before THEN
    RETURN jsonb_build_object('applied', false, 'reason', 'job_not_finishing');
  END IF;
  v_would := p_printed_after >= p_quantity_before;

  SELECT id, quantity, notes, "productOrderId", "productPartId" INTO j
  FROM "print-farm"."ProductionJob" WHERE id = p_job_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('applied', false, 'reason', 'job_not_found');
  END IF;

  SELECT f.status::text INTO v_file_status
  FROM "print-farm"."_JobsToFiles" x
  JOIN "print-farm"."ProjectThreeMFFile" f ON f.id = x."B"
  WHERE x."A" = p_job_id
  ORDER BY f.version DESC LIMIT 1;
  IF v_file_status IS NULL THEN
    RETURN jsonb_build_object('applied', false, 'reason', 'no_file');
  END IF;
  IF v_file_status NOT IN ('DRAFT', 'APPROVED') THEN
    RETURN jsonb_build_object('applied', false, 'reason', 'file_' || lower(v_file_status));
  END IF;

  IF v_would THEN
    v_new_q := greatest(j.quantity, p_printed_after) + p_rejected;
    v_note := format('Riapertura automatica per %s scarti a fine job (evita swap filamento)', p_rejected);
    UPDATE "print-farm"."ProductionJob"
    SET quantity = v_new_q, status = 'IN_PROGRESS', "finishedAt" = NULL,
        notes = CASE WHEN position(v_note IN coalesce(notes, '')) > 0 THEN notes
                     ELSE concat_ws(' | ', nullif(notes, ''), v_note) END,
        "updatedAt" = now()
    WHERE id = p_job_id;
    IF j."productOrderId" IS NOT NULL AND j."productPartId" IS NOT NULL THEN
      UPDATE inventory."ProductOrderProductPart"
      SET quantity = quantity + p_rejected
      WHERE "productOrderId" = j."productOrderId" AND "productPartId" = j."productPartId";
    END IF;
  ELSE
    UPDATE "print-farm"."ProductionJob"
    SET status = 'IN_PROGRESS', "finishedAt" = NULL, "updatedAt" = now()
    WHERE id = p_job_id;
  END IF;

  WITH c AS (
    UPDATE "print-farm"."PrinterAssignment"
    SET status = 'CANCELLED', "completedAt" = now(),
        notes = format('Cancellato: ristampa scarti a fine job %s (stesso materiale prioritario)', p_job_id),
        "updatedAt" = now()
    WHERE "printerId" = p_printer_id AND status = 'SCHEDULED'
      AND ("productionJobId" IS NULL OR "productionJobId" <> p_job_id)
    RETURNING id
  )
  SELECT array_agg(id) INTO v_cancelled FROM c;

  RETURN jsonb_build_object(
    'applied', true,
    'reason', CASE WHEN v_would THEN 'reopened_for_scraps' ELSE 'shortfall_reprint' END,
    'quantityBump', CASE WHEN v_would THEN p_rejected ELSE 0 END,
    'orderPartBump', CASE WHEN v_would AND j."productOrderId" IS NOT NULL AND j."productPartId" IS NOT NULL
                          THEN p_rejected ELSE 0 END,
    'newQuantity', CASE WHEN v_would THEN v_new_q END,
    'cancelledScheduledIds', coalesce(to_jsonb(v_cancelled), '[]'::jsonb)
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- Ristampa urgente sulla stessa stampante (ensureUrgentNextScheduledForJob, D-05)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "print-farm"._pf_harvest_urgent_next(
  p_job_id uuid, p_printer_id uuid, p_serial text, p_material text, p_color text,
  p_exclude_id uuid, p_failure_streak boolean, p_template jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  j record;
  f record;
  v_cap int;
  v_remaining int;
  v_outstanding int;
  v_need int;
  e record;
  v_parts int;
  v_payload jsonb;
  v_id uuid;
BEGIN
  SELECT id, quantity, "quantityPrinted" INTO j FROM "print-farm"."ProductionJob" WHERE id = p_job_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('action', 'none', 'reason', 'job_not_found'); END IF;
  SELECT f2.id, f2."partCount" INTO f
  FROM "print-farm"."_JobsToFiles" x JOIN "print-farm"."ProjectThreeMFFile" f2 ON f2.id = x."B"
  WHERE x."A" = p_job_id ORDER BY f2.version DESC LIMIT 1;
  IF NOT FOUND THEN RETURN jsonb_build_object('action', 'none', 'reason', 'no_file'); END IF;

  v_cap := CASE WHEN coalesce(f."partCount", 0) > 0 THEN f."partCount" ELSE 1 END;
  v_remaining := greatest(0, coalesce(j.quantity, 0) - coalesce(j."quantityPrinted", 0));
  IF v_remaining <= 0 THEN RETURN jsonb_build_object('action', 'none', 'reason', 'job_complete'); END IF;

  SELECT coalesce(sum(greatest(0, coalesce("partsExpected", 0) - (coalesce("partsProduced", 0) + coalesce("partsRejected", 0)))), 0)
  INTO v_outstanding
  FROM "print-farm"."PrinterAssignment"
  WHERE "productionJobId" = p_job_id
    AND status::text IN ('SCHEDULED', 'QUEUED', 'PRINTING', 'TO_HARVEST')
    AND (p_exclude_id IS NULL OR id <> p_exclude_id);

  v_need := v_remaining - v_outstanding;
  IF v_need <= 0 THEN RETURN jsonb_build_object('action', 'none', 'reason', 'planned_enough'); END IF;
  IF coalesce(p_failure_streak, false) THEN
    RETURN jsonb_build_object('action', 'none', 'reason', 'failure_streak', 'need', v_need);
  END IF;

  SELECT id, "productionJobId", "partsExpected" INTO e
  FROM "print-farm"."PrinterAssignment"
  WHERE "printerId" = p_printer_id AND status = 'SCHEDULED'
  ORDER BY "queuePosition" ASC, "scheduledAt" ASC NULLS LAST
  LIMIT 1
  FOR UPDATE;

  IF FOUND AND e."productionJobId" IS NOT NULL AND e."productionJobId" <> p_job_id THEN
    RETURN jsonb_build_object('action', 'none', 'reason', 'foreign_scheduled', 'need', v_need);
  END IF;

  v_parts := CASE WHEN e.id IS NOT NULL THEN least(v_cap, coalesce(e."partsExpected", 0) + v_need)
                  ELSE least(v_cap, v_need) END;
  v_payload := "print-farm"._pf_harvest_start_payload(f.id, p_serial, v_parts, p_template);

  IF e.id IS NOT NULL THEN
    UPDATE "print-farm"."PrinterAssignment"
    SET "productionJobId" = p_job_id, "queuePosition" = 0, status = 'SCHEDULED', "scheduledAt" = now(),
        "partsExpected" = v_parts, "materialRequired" = p_material, "colorRequired" = p_color,
        "startPayload" = v_payload,
        notes = 'Replanned by harvest (bulk-single rejects) - urgent next job',
        "updatedAt" = now()
    WHERE id = e.id;
    RETURN jsonb_build_object('action', 'updated', 'assignmentId', e.id, 'parts', v_parts,
                              'previousParts', e."partsExpected");
  END IF;

  INSERT INTO "print-farm"."PrinterAssignment" (
    id, "productionJobId", "printerId", "queuePosition", status, "scheduledAt", "partsExpected",
    "materialRequired", "colorRequired", "startPayload", notes, "updatedAt"
  ) VALUES (
    gen_random_uuid(), p_job_id, p_printer_id, 0, 'SCHEDULED', now(), v_parts,
    p_material, p_color, v_payload, 'Replanned by harvest (bulk-single rejects) - created urgent next job', now()
  ) RETURNING id INTO v_id;
  RETURN jsonb_build_object('action', 'created', 'assignmentId', v_id, 'parts', v_parts);
END;
$$;

-- ---------------------------------------------------------------------------
-- Manutenzione allo scarico (applyPrinterOverrideChange → MAINTENANCE)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "print-farm"._pf_harvest_set_maintenance(
  p_printer_id uuid, p_reason text, p_user_id int, p_source text
) RETURNS void
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_current text;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_actor text := CASE WHEN p_user_id IS NULL THEN NULL ELSE p_user_id::text END;
BEGIN
  SELECT "manualOverrideStatus"::text INTO v_current FROM "print-farm"."Printer" WHERE id = p_printer_id;
  IF v_current = 'MAINTENANCE' THEN
    UPDATE "print-farm"."Printer"
    SET "manualOverrideReason" = v_reason, "manualOverrideBy" = v_actor, "manualOverrideAt" = now(), "updatedAt" = now()
    WHERE id = p_printer_id;
    RETURN;
  END IF;
  UPDATE "print-farm"."PrinterOverridePeriod"
  SET "endedAt" = now(), "clearedByUserId" = v_actor, "updatedAt" = now()
  WHERE "printerId" = p_printer_id AND "endedAt" IS NULL;
  INSERT INTO "print-farm"."PrinterOverridePeriod" (id, "printerId", status, "startedAt", "setByUserId", reason, source, "updatedAt")
  VALUES (gen_random_uuid(), p_printer_id, 'MAINTENANCE', now(), v_actor, v_reason, p_source, now());
  UPDATE "print-farm"."Printer"
  SET "manualOverrideStatus" = 'MAINTENANCE', "manualOverrideReason" = v_reason,
      "manualOverrideBy" = v_actor, "manualOverrideAt" = now(), "updatedAt" = now()
  WHERE id = p_printer_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- Una riga del giro. Ritorna l'esito; un conflitto torna `ok: false` e il
-- chiamante annulla la sotto-transazione. Le violazioni di invariante sono RAISE.
-- ---------------------------------------------------------------------------
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
  IF v_mode <> 'COUNT' THEN
    RETURN "print-farm"._pf_harvest_fail('INVALID', 'Modalità non ancora disponibile: ' || v_mode, 400, false);
  END IF;
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
      (SELECT s."spoolId" FROM "print-farm"."PrinterAmsSlot" s
       WHERE s."printerId" = v_printer_id AND s."spoolId" IS NOT NULL
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
  v_blocked := v_set_maint OR coalesce(pr.override, '') IN ('MAINTENANCE', 'DISABLED');

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
  IF v_remaining > 0 THEN
    v_text := coalesce(v_notes,
      CASE WHEN p_source = 'DETAIL' THEN '' ELSE format('Scarico bulk progressivo - %s OK, %s scarti', v_acc, v_rej) END);
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
  v_should_complete := v_complete OR v_remaining <= 0;

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
    SET status = 'COMPLETED', "completedAt" = now(), "updatedAt" = now()
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
    IF NOT EXISTS (SELECT 1 FROM "print-farm"."PrinterHarvest" WHERE id = v_harvest_id
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

-- ---------------------------------------------------------------------------
-- Giro di scarico: una istruzione, una sotto-transazione per riga.
-- ---------------------------------------------------------------------------
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
      v_result := "print-farm"._pf_harvest_apply_item(v_item, v_operator, v_source);
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

-- Solo il ruolo dell'app: mai da PostgREST.
REVOKE ALL ON FUNCTION "print-farm"._pf_harvest_fail(text, text, int, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION "print-farm"._pf_harvest_start_payload(uuid, text, int, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION "print-farm"._pf_harvest_inventory_lot(uuid, uuid, uuid, int) FROM PUBLIC;
REVOKE ALL ON FUNCTION "print-farm"._pf_harvest_mark_odette_full(uuid, int, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION "print-farm"._pf_harvest_order_rollup(uuid, uuid, int, int) FROM PUBLIC;
REVOKE ALL ON FUNCTION "print-farm"._pf_harvest_spool_reconcile(uuid, jsonb, numeric, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION "print-farm"._pf_harvest_end_of_job_scraps(uuid, uuid, int, int, int) FROM PUBLIC;
REVOKE ALL ON FUNCTION "print-farm"._pf_harvest_urgent_next(uuid, uuid, text, text, text, uuid, boolean, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION "print-farm"._pf_harvest_set_maintenance(uuid, text, int, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION "print-farm"._pf_harvest_apply_item(jsonb, int, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION "print-farm".pf_harvest_apply(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION "print-farm".pf_harvest_context(uuid[], jsonb) FROM PUBLIC;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON FUNCTION "print-farm".pf_harvest_apply(jsonb) FROM anon';
    EXECUTE 'REVOKE ALL ON FUNCTION "print-farm".pf_harvest_context(uuid[], jsonb) FROM anon';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    EXECUTE 'REVOKE ALL ON FUNCTION "print-farm".pf_harvest_apply(jsonb) FROM authenticated';
    EXECUTE 'REVOKE ALL ON FUNCTION "print-farm".pf_harvest_context(uuid[], jsonb) FROM authenticated';
  END IF;
END $$;
