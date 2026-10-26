-- ============================================================================
-- Concludi di swap e runout in una sola istruzione SQL (fase 1 di
-- docs/swap-rpc-progetto.md, decisioni utente 26/10: D-S01…D-S08)
--
-- Oggi Concludi fa due GET in parallelo e poi PATCH operational-status: 2
-- richieste HTTP in fila e 5 query, ognuna ~80 ms di rete verso il DB. La
-- scrittura non ricontrolla niente: se fra la lettura e la PATCH la stampante
-- riparte, un Concludi di runout la riporta AVAILABLE; due tablet scrivono
-- entrambi.
--
-- Con `pf_swap_conclude` la route `POST /api/printers/[id]/swap-conclude` fa
-- i controlli in TypeScript su una sola lettura e poi chiama questa funzione,
-- che sotto lock:
--   1. ricontrolla la bobina montata nel punto del cambio;
--   2. ricontrolla il flag di cambio (riacceso per un altro job → FLAG_CHANGED);
--   3. non riporta AVAILABLE una stampante già PRINTING o QUEUED, né nel runout
--      né nello swap (D-S02, esteso allo swap il 26/10): spegne solo il flag;
--   4. da ERROR riporta in coda gli START_FAILED una volta sola, come la PATCH;
--   5. scrive lo stato e spegne il flag.
-- Non scrive PrinterStateEvent, come la PATCH: D-S03 è sospesa perché le
-- sessioni di runout contano su questa assenza (session-lifecycle.ts,
-- resolveRunoutLeftAt).
--
-- Un conflitto atteso torna come esito (`ok: false`, `code`, `http`), non come
-- eccezione. Solo gli errori di Postgres (lock_timeout 55P03, deadlock 40P01)
-- sono eccezioni: la route li traduce in 503 ritentabile.
--
-- Ordine dei lock (uguale per Concludi, Cambia, scarico e avvio stampa):
--   1. pg_advisory_xact_lock(hashtext(printerId))  stesso lock del backend
--      (queue_task_processor.js) e del progetto pf_harvest_*;
--   2. filament_mount (slot o bobina), condiviso: aspetta un montaggio in corso
--      sullo stesso slot (che lo prende esclusivo);
--   3. riga Printer FOR NO KEY UPDATE (non blocca gli INSERT con FK verso Printer).
-- Il montaggio di oggi prende 2 e poi scrive la riga Printer (3): stesso ordine,
-- nessun deadlock.
--
-- Sicurezza: chiamabili solo dal ruolo dell'app. `anon` ha USAGE sullo schema
-- "print-farm" e una funzione nuova è eseguibile da PUBLIC per default.
--
-- Nessun dato toccato. Senza il codice nuovo (o con SWAP_RPC=off) le funzioni
-- non le chiama nessuno. Idempotente: CREATE OR REPLACE.
-- ============================================================================

-- Lock per stampante condiviso con il backend (avvio stampa) e con lo scarico.
-- Il backend usa hashtext(String(printerId)): uuid::text è lo stesso testo.
CREATE OR REPLACE FUNCTION "print-farm"._pf_lock_printer(p_printer_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(p_printer_id::text));
END;
$$;

-- Esito di errore nel formato comune delle pf_swap_*.
CREATE OR REPLACE FUNCTION "print-farm"._pf_swap_fail(p_code text, p_http integer, p_detail jsonb DEFAULT NULL)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
    'v', 1, 'ok', false, 'code', p_code, 'http', p_http, 'detail', p_detail
  ));
$$;

-- Ingresso (versione 1):
-- {
--   "v": 1,
--   "printerId": "uuid",
--   "isRunout": true,
--   "mount": null                                         -- Filo spezzato: nessun controllo
--          | { "kind": "ams_slot", "amsUnit": 1, "slot": 0, "spoolId": "uuid" | null }
--          | { "kind": "spool_on_printer", "spoolId": "uuid" }
--          | { "kind": "printer_current" },
--   "seenNeedsFilamentSwapAt": "2026-10-26T09:12:33.123Z" | null,
--   "operationId": "uuid", "reason": "swap-done-v3"       -- solo eco nella risposta
-- }
-- Uscita: { "v": 1, "ok": true, "alreadyClean": bool, "statusKept": bool,
--           "previousStatus": "...", "operationalStatus": "...", "selfHealed": n }
--      oppure { "v": 1, "ok": false, "code": "...", "http": 409, "detail": {...} }
CREATE OR REPLACE FUNCTION "print-farm".pf_swap_conclude(p jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
SET lock_timeout = '3s'
AS $$
DECLARE
  c_uuid_re constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_printer_id uuid;
  v_is_runout boolean;
  v_mount jsonb;
  v_mount_kind text;
  v_ams_unit integer;
  v_slot integer;
  v_expected_spool uuid;
  v_slot_found boolean;
  v_slot_spool uuid;
  v_seen_at_raw jsonb;
  v_seen_at timestamptz;
  v_status public.printer_operational_status;
  v_needs boolean;
  v_needs_at timestamptz;
  v_current_spool uuid;
  v_keep_status boolean;
  v_target public.printer_operational_status;
  v_healed integer := 0;
BEGIN
  -- ---- Ingresso -----------------------------------------------------------
  IF p IS NULL OR pg_catalog.jsonb_typeof(p) <> 'object' OR p->>'v' IS DISTINCT FROM '1' THEN
    RETURN "print-farm"._pf_swap_fail('INVALID', 400, pg_catalog.jsonb_build_object('field', 'v'));
  END IF;
  IF coalesce(p->>'printerId', '') !~ c_uuid_re THEN
    RETURN "print-farm"._pf_swap_fail('INVALID', 400, pg_catalog.jsonb_build_object('field', 'printerId'));
  END IF;
  v_printer_id := (p->>'printerId')::uuid;
  IF pg_catalog.jsonb_typeof(p->'isRunout') IS DISTINCT FROM 'boolean' THEN
    RETURN "print-farm"._pf_swap_fail('INVALID', 400, pg_catalog.jsonb_build_object('field', 'isRunout'));
  END IF;
  v_is_runout := (p->>'isRunout')::boolean;

  v_mount := p->'mount';
  IF v_mount IS NOT NULL AND pg_catalog.jsonb_typeof(v_mount) = 'null' THEN
    v_mount := NULL;
  END IF;
  IF v_mount IS NOT NULL THEN
    IF pg_catalog.jsonb_typeof(v_mount) <> 'object' THEN
      RETURN "print-farm"._pf_swap_fail('INVALID', 400, pg_catalog.jsonb_build_object('field', 'mount'));
    END IF;
    v_mount_kind := v_mount->>'kind';
    IF v_mount_kind = 'ams_slot' THEN
      IF pg_catalog.jsonb_typeof(v_mount->'amsUnit') IS DISTINCT FROM 'number'
         OR pg_catalog.jsonb_typeof(v_mount->'slot') IS DISTINCT FROM 'number'
         OR (v_mount->>'amsUnit') !~ '^[0-9]{1,3}$'
         OR (v_mount->>'slot') !~ '^[0-9]{1,2}$' THEN
        RETURN "print-farm"._pf_swap_fail('INVALID', 400, pg_catalog.jsonb_build_object('field', 'mount.slot'));
      END IF;
      v_ams_unit := (v_mount->>'amsUnit')::integer;
      v_slot := (v_mount->>'slot')::integer;
      IF v_mount->>'spoolId' IS NOT NULL THEN
        IF (v_mount->>'spoolId') !~ c_uuid_re THEN
          RETURN "print-farm"._pf_swap_fail('INVALID', 400, pg_catalog.jsonb_build_object('field', 'mount.spoolId'));
        END IF;
        v_expected_spool := (v_mount->>'spoolId')::uuid;
      END IF;
    ELSIF v_mount_kind = 'spool_on_printer' THEN
      IF coalesce(v_mount->>'spoolId', '') !~ c_uuid_re THEN
        RETURN "print-farm"._pf_swap_fail('INVALID', 400, pg_catalog.jsonb_build_object('field', 'mount.spoolId'));
      END IF;
      v_expected_spool := (v_mount->>'spoolId')::uuid;
    ELSIF v_mount_kind IS DISTINCT FROM 'printer_current' THEN
      RETURN "print-farm"._pf_swap_fail('INVALID', 400, pg_catalog.jsonb_build_object('field', 'mount.kind'));
    END IF;
  END IF;

  v_seen_at_raw := p->'seenNeedsFilamentSwapAt';
  IF v_seen_at_raw IS NOT NULL AND pg_catalog.jsonb_typeof(v_seen_at_raw) = 'string' THEN
    BEGIN
      v_seen_at := (v_seen_at_raw #>> '{}')::timestamptz;
    EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN
      RETURN "print-farm"._pf_swap_fail('INVALID', 400, pg_catalog.jsonb_build_object('field', 'seenNeedsFilamentSwapAt'));
    END;
  ELSIF v_seen_at_raw IS NOT NULL AND pg_catalog.jsonb_typeof(v_seen_at_raw) <> 'null' THEN
    RETURN "print-farm"._pf_swap_fail('INVALID', 400, pg_catalog.jsonb_build_object('field', 'seenNeedsFilamentSwapAt'));
  END IF;

  -- ---- Fase A: lock e controlli, nessuna scrittura -------------------------
  PERFORM "print-farm"._pf_lock_printer(v_printer_id);

  -- Stesse chiavi del montaggio (ams-slots/swap-spool `acquireMountLock`), in
  -- modo condiviso: un Cambia in corso sullo stesso slot finisce prima.
  IF v_mount_kind = 'ams_slot' THEN
    PERFORM pg_catalog.pg_advisory_xact_lock_shared(
      pg_catalog.hashtext('filament_mount'),
      pg_catalog.hashtext(pg_catalog.format('printer:%s:ams:%s:%s', v_printer_id, v_ams_unit, v_slot))
    );
  ELSIF v_mount_kind = 'spool_on_printer' THEN
    PERFORM pg_catalog.pg_advisory_xact_lock_shared(
      pg_catalog.hashtext('filament_mount'),
      pg_catalog.hashtext(pg_catalog.format('spool:%s', v_expected_spool))
    );
  END IF;

  SELECT pr."operationalStatus", pr."needsFilamentSwap", pr."needsFilamentSwapAt", pr."currentSpoolId"
    INTO v_status, v_needs, v_needs_at, v_current_spool
  FROM "print-farm"."Printer" pr
  WHERE pr.id = v_printer_id
  FOR NO KEY UPDATE;
  IF NOT FOUND THEN
    RETURN "print-farm"._pf_swap_fail('NOT_FOUND', 404, NULL);
  END IF;

  -- Bobina montata: la stessa condizione già verificata dalla route, rifatta
  -- sotto lock (un altro tablet può averla cambiata nel frattempo).
  IF v_mount_kind = 'ams_slot' THEN
    SELECT true, s."spoolId" INTO v_slot_found, v_slot_spool
    FROM "print-farm"."PrinterAmsSlot" s
    WHERE s."printerId" = v_printer_id AND s."amsUnit" = v_ams_unit AND s.slot = v_slot;
    IF v_slot_spool IS NULL THEN
      RETURN "print-farm"._pf_swap_fail('NOT_MOUNTED_SLOT', 409, NULL);
    END IF;
    IF v_expected_spool IS NOT NULL AND v_slot_spool <> v_expected_spool THEN
      RETURN "print-farm"._pf_swap_fail('WRONG_SPOOL', 409,
        pg_catalog.jsonb_build_object('mountedSpoolId', v_slot_spool));
    END IF;
  ELSIF v_mount_kind = 'spool_on_printer' THEN
    IF NOT EXISTS (
      SELECT 1 FROM "print-farm"."FilamentSpool" fs
      WHERE fs.id = v_expected_spool AND fs."mountedOnId" = v_printer_id
    ) THEN
      RETURN "print-farm"._pf_swap_fail('SPOOL_NOT_MOUNTED', 409, NULL);
    END IF;
  ELSIF v_mount_kind = 'printer_current' THEN
    IF v_current_spool IS NULL THEN
      RETURN "print-farm"._pf_swap_fail('NOT_MOUNTED', 409, NULL);
    END IF;
  END IF;

  -- D-S02, esteso allo swap dall'utente il 26/10: con la stampante in stampa
  -- o in coda Concludi non la riporta AVAILABLE; si spegne solo il flag.
  v_keep_status := v_status IN ('PRINTING', 'QUEUED');
  v_target := CASE WHEN v_keep_status THEN v_status ELSE 'AVAILABLE'::public.printer_operational_status END;

  -- Già concluso (altro tablet, ritentativo): stessa regola della route
  -- (`isConcludeAlreadyClean`), nessuna scrittura.
  IF NOT v_needs AND (NOT v_is_runout OR v_status IN ('AVAILABLE', 'PRINTING', 'QUEUED')) THEN
    RETURN pg_catalog.jsonb_build_object(
      'v', 1, 'ok', true, 'alreadyClean', true, 'statusKept', v_keep_status,
      'previousStatus', v_status::text, 'operationalStatus', v_status::text, 'selfHealed', 0,
      'operationId', p->>'operationId'
    );
  END IF;

  -- Flag riacceso dopo la lettura della route (un altro job chiede un cambio):
  -- la corrispondenza del filamento controllata in TypeScript non vale più.
  IF v_needs
     AND pg_catalog.date_trunc('milliseconds', v_needs_at) IS DISTINCT FROM pg_catalog.date_trunc('milliseconds', v_seen_at) THEN
    RETURN "print-farm"._pf_swap_fail('FLAG_CHANGED', 409, NULL);
  END IF;

  -- ---- Fase B: scritture --------------------------------------------------
  -- Self-heal one-shot, identico alla PATCH operational-status.
  IF v_status = 'ERROR' AND v_target <> 'ERROR' THEN
    UPDATE "print-farm"."PrinterAssignment" a
    SET status = 'QUEUED'::public.assignment_status,
        "claimedAt" = NULL,
        "startedAt" = NULL,
        "updatedAt" = now(),
        notes = CASE
          WHEN a.notes IS NULL OR a.notes = '' THEN '[self-healed] Auto-requeued: stato stampante cambiato manualmente'
          ELSE a.notes || E'\n' || '[self-healed] Auto-requeued: stato stampante cambiato manualmente'
        END
    WHERE a."printerId" = v_printer_id
      AND a.status = 'START_FAILED'::public.assignment_status
      AND (a.notes IS NULL OR a.notes NOT LIKE '%[self-healed]%');
    GET DIAGNOSTICS v_healed = ROW_COUNT;
  END IF;

  UPDATE "print-farm"."Printer"
  SET "operationalStatus" = v_target,
      "needsFilamentSwap" = false,
      "needsFilamentSwapAt" = NULL,
      "updatedAt" = now()
  WHERE id = v_printer_id;

  RETURN pg_catalog.jsonb_build_object(
    'v', 1, 'ok', true, 'alreadyClean', false, 'statusKept', v_keep_status,
    'previousStatus', v_status::text, 'operationalStatus', v_target::text, 'selfHealed', v_healed,
    'operationId', p->>'operationId'
  );
END;
$$;

REVOKE ALL ON FUNCTION "print-farm"._pf_lock_printer(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION "print-farm"._pf_swap_fail(text, integer, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION "print-farm".pf_swap_conclude(jsonb) FROM PUBLIC;

DO $$
DECLARE
  r text;
BEGIN
  FOREACH r IN ARRAY ARRAY['anon', 'authenticated'] LOOP
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = r) THEN
      EXECUTE pg_catalog.format('REVOKE ALL ON FUNCTION "print-farm"._pf_lock_printer(uuid) FROM %I', r);
      EXECUTE pg_catalog.format('REVOKE ALL ON FUNCTION "print-farm"._pf_swap_fail(text, integer, jsonb) FROM %I', r);
      EXECUTE pg_catalog.format('REVOKE ALL ON FUNCTION "print-farm".pf_swap_conclude(jsonb) FROM %I', r);
    END IF;
  END LOOP;
END;
$$;
