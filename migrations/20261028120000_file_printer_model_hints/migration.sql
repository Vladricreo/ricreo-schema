-- Modello stampante suggerito per un file 3MF (28/10).
-- Bambu Studio scrive in `slice_info.config` un codice modello (`printer_model_id`:
-- N6 = X2D, C12 = P1S, BL-P001 = X1C, ...). La view impara il legame dai file gia'
-- caricati: per ogni codice, su quali modelli (`compatiblePrinters`) sono stati
-- messi i file e con che quota. All'upload il dialog suggerisce i modelli con quota
-- alta e avvisa se le stampanti scelte non tornano (file X2D messo su P1S/X1C).
-- Esclusi i file REJECTED (spesso scartati proprio perche' sul modello sbagliato).

CREATE OR REPLACE VIEW "print_farm_views"."v_pf_file_printer_model_hints" AS
WITH files AS (
  SELECT upper(btrim(f."printerModelId")) AS slicer_model_id, f."compatiblePrinters", f."extruderTypes"
  FROM "print-farm"."ProjectThreeMFFile" f
  WHERE nullif(btrim(f."printerModelId"), '') IS NOT NULL AND f."status"::text <> 'REJECTED'
), totals AS (
  SELECT slicer_model_id, count(*)::int AS total_files,
         round(avg(cardinality("extruderTypes")) FILTER (WHERE cardinality("extruderTypes") > 0), 2) AS avg_extruders
  FROM files GROUP BY slicer_model_id
)
SELECT f.slicer_model_id AS "slicerModelId", pm."name" AS "printerModelName", pm."nozzleCount" AS "nozzleCount",
       count(*)::int AS "filesCount", t.total_files AS "totalFiles",
       round(count(*)::numeric / t.total_files, 3) AS "share", t.avg_extruders AS "avgFileExtruders"
FROM files f
CROSS JOIN LATERAL unnest(f."compatiblePrinters") AS cp(name)
JOIN "print-farm"."PrinterModel" pm ON pm."name" = cp.name
JOIN totals t ON t.slicer_model_id = f.slicer_model_id
GROUP BY f.slicer_model_id, pm."name", pm."nozzleCount", t.total_files, t.avg_extruders;
