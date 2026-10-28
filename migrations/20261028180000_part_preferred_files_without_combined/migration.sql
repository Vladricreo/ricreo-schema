-- Piatti combinati, fase 1 (guardia), decisione utente 28/10 (R-122, piano
-- `audits/2026-10-28-piatti-combinati/PIANO.md`).
-- Un file con righe `ProjectPart` di più ProductPart diverse (piatto combinato)
-- non è mai il file "della parte": la vista lo esclude. Stesse colonne di
-- 20260622140000_part_preferred_files_view, quindi CREATE OR REPLACE (tiene i
-- permessi). I combinati avranno un percorso loro (fasi 4 e 6 del piano).

CREATE OR REPLACE VIEW "print_farm_views"."v_pf_part_preferred_files" AS
WITH RECURSIVE
chain AS (
  SELECT
    f."id"                AS file_id,
    f."previousVersionId" AS prev_id,
    f."id"                AS root_id
  FROM "print-farm"."ProjectThreeMFFile" f
  WHERE f."previousVersionId" IS NULL
  UNION ALL
  SELECT
    f."id"                AS file_id,
    f."previousVersionId" AS prev_id,
    c.root_id             AS root_id
  FROM "print-farm"."ProjectThreeMFFile" f
  JOIN chain c ON f."previousVersionId" = c.file_id
),
-- File combinati: più ProductPart distinte nelle righe ProjectPart.
combined_files AS (
  SELECT pp."fileId" AS file_id
  FROM "print-farm"."ProjectPart" pp
  WHERE pp."productPartId" IS NOT NULL
  GROUP BY pp."fileId"
  HAVING count(DISTINCT pp."productPartId") > 1
),
part_files AS (
  SELECT f."id" AS file_id, f."productPartId" AS part_id
  FROM "print-farm"."ProjectThreeMFFile" f
  WHERE f."productPartId" IS NOT NULL
  UNION
  SELECT pp."fileId" AS file_id, pp."productPartId" AS part_id
  FROM "print-farm"."ProjectPart" pp
  WHERE pp."productPartId" IS NOT NULL
),
candidates AS (
  SELECT
    pf.part_id,
    c.root_id,
    f."id"                       AS file_id,
    f."version"                  AS version,
    f."status"::text             AS status,
    f."partCount"                AS part_count,
    f."compatiblePrinters"       AS compatible_printers,
    f."estimatedDurationMinutes" AS estimated_minutes,
    f."createdAt"                AS created_at,
    CASE f."status"
      WHEN 'APPROVED' THEN 2
      WHEN 'DRAFT'    THEN 1
      ELSE 0
    END AS status_rank
  FROM part_files pf
  JOIN "print-farm"."ProjectThreeMFFile" f ON f."id" = pf.file_id
  JOIN chain c ON c.file_id = f."id"
  WHERE f."status" IN ('APPROVED', 'DRAFT')
    AND NOT EXISTS (SELECT 1 FROM combined_files cf WHERE cf.file_id = f."id")
)
SELECT DISTINCT ON (part_id, root_id)
  part_id                              AS "productPartId",
  root_id                              AS "variantRootId",
  file_id                              AS "fileId",
  version                              AS "version",
  status                               AS "status",
  CASE WHEN status_rank = 2 THEN 'approved' ELSE 'draft' END AS "selection",
  part_count                           AS "partCount",
  compatible_printers                  AS "compatiblePrinters",
  estimated_minutes                    AS "estimatedDurationMinutes"
FROM candidates
ORDER BY part_id, root_id, status_rank DESC, version DESC, created_at DESC;

COMMENT ON VIEW "print_farm_views"."v_pf_part_preferred_files" IS
  'Per (ProductPart, variante lineage) il file 3MF preferito (APPROVED>DRAFT), esclusi i piatti combinati (28/10). Multi-variante = piu'' righe per parte.';
