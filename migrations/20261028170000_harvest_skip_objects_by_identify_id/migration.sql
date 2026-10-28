-- Regola unica dello skip objects (decisione utente 28/10, audit
-- `audits/2026-10-28-piatti-combinati/AUDIT.md`, trappola 3).
-- Uguale a `client/src/lib/files/skip-objects.ts` e `backend/src/utils/skip-objects.js`:
-- oggetti attivi del piatto in ordine di identifyId crescente (prima: ordine del
-- JSON, diverso dall'ordine per id in 13 file attivi al 28/10); si stampano i primi
-- ceil(p_parts × oggetti/pezzo) e si saltano gli altri.
-- Solo il blocco degli oggetti cambia; il resto della funzione è identico a
-- 20261027090000_harvest_rpc_functions.

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
  v_n_active int;
  v_to_print int;
  v_template_ok boolean;
  v_options jsonb;
  v_payload jsonb;
BEGIN
  IF p_serial IS NULL OR p_file_id IS NULL THEN
    RETURN NULL;
  END IF;
  SELECT id, filename, "plateNumber", "partCount", "sliceObjects" INTO f
  FROM "print-farm"."ProjectThreeMFFile" WHERE id = p_file_id;
  IF NOT FOUND OR f.filename IS NULL THEN
    RETURN NULL;
  END IF;

  v_filename := CASE
    WHEN f.filename LIKE '%.gcode.3mf' THEN f.filename
    WHEN f.filename LIKE '%.3mf' THEN regexp_replace(f.filename, '\.3mf', '.gcode.3mf')
    ELSE f.filename || '.gcode.3mf'
  END;

  -- Oggetti attivi per identifyId crescente (regola unica dello skip).
  IF jsonb_typeof(f."sliceObjects") = 'array' THEN
    SELECT array_agg(x.ident ORDER BY x.ident)
    INTO v_active
    FROM (
      SELECT (o->>'identifyId')::numeric::int AS ident
      FROM jsonb_array_elements(f."sliceObjects") AS e(o)
      WHERE (o->>'identifyId') ~ '^-?[0-9]+(\.[0-9]+)?$'
        AND coalesce(o->>'skipped', 'false') IN ('false', '0', '', 'null')
    ) x;
  END IF;
  v_n_active := coalesce(array_length(v_active, 1), 0);
  IF v_n_active > 1 AND p_parts > 0 THEN
    -- Un pezzo fatto da più oggetti: oggetti/pezzo = attivi / partCount.
    v_to_print := CASE
      WHEN coalesce(f."partCount", 0) > 0 AND v_n_active > f."partCount"
        THEN ceil(p_parts::numeric * v_n_active / f."partCount")::int
      ELSE p_parts
    END;
    IF v_to_print < v_n_active THEN
      v_skip := v_active[v_to_print + 1 : v_n_active];
    END IF;
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
