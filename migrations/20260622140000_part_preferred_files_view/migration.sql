-- ============================================================================
-- PRINT FARM — PART PREFERRED FILES (per variante)
-- Schema: "print_farm_views"
-- Descrizione:
--   View read-only che, per ogni (ProductPart, variante di file), espone il file
--   3MF "preferito" da usare in produzione.
--
--   Concetto di "variante" (lineage):
--     Due file appartengono alla stessa variante se sono nella stessa catena di
--     versioni (`previousVersionId`). La "radice" della catena identifica la
--     variante. Le nuove versioni ereditano `compatiblePrinters`, quindi una
--     variante = "stesso deliverable, stesso gruppo di stampanti". Upload distinti
--     (es. uno per X1C/P1S, uno per X2D) sono lineage diversi -> varianti diverse.
--
--   Selezione del file preferito DENTRO una variante (come `selectPreferredFile`):
--     - ultima versione APPROVED, altrimenti
--     - ultima versione DRAFT, altrimenti
--     - la variante non viene esposta (nessun file utilizzabile).
--
--   Output: una riga per (productPartId, variantRootId). Una parte con piu'
--   lineage compatibili con stampanti diverse produce piu' righe, cosi' lo
--   scheduler puo' considerarle tutte come alternative (ognuna col proprio
--   partCount / compatiblePrinters).
-- ============================================================================

DROP VIEW IF EXISTS "print_farm_views"."v_pf_part_preferred_files";

CREATE VIEW "print_farm_views"."v_pf_part_preferred_files" AS
WITH RECURSIVE
-- 1) Calcola la radice (variantRootId) di ogni file risalendo la catena versioni.
chain AS (
  -- Radici: file senza versione precedente.
  SELECT
    f."id"                AS file_id,
    f."previousVersionId" AS prev_id,
    f."id"                AS root_id
  FROM "print-farm"."ProjectThreeMFFile" f
  WHERE f."previousVersionId" IS NULL
  UNION ALL
  -- Discendenti: ereditano la radice del genitore.
  SELECT
    f."id"                AS file_id,
    f."previousVersionId" AS prev_id,
    c.root_id             AS root_id
  FROM "print-farm"."ProjectThreeMFFile" f
  JOIN chain c ON f."previousVersionId" = c.file_id
),
-- 2) Associazione file -> ProductPart: sia diretta (`productPartId`) sia tramite
--    le righe `ProjectPart` (multi-parte). Si unificano in un unico elenco.
part_files AS (
  SELECT f."id" AS file_id, f."productPartId" AS part_id
  FROM "print-farm"."ProjectThreeMFFile" f
  WHERE f."productPartId" IS NOT NULL
  UNION
  SELECT pp."fileId" AS file_id, pp."productPartId" AS part_id
  FROM "print-farm"."ProjectPart" pp
  WHERE pp."productPartId" IS NOT NULL
),
-- 3) Solo file utilizzabili in produzione (APPROVED/DRAFT) con metadati e radice.
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
    -- Priorita' status: APPROVED batte sempre DRAFT (a prescindere dalla versione).
    CASE f."status"
      WHEN 'APPROVED' THEN 2
      WHEN 'DRAFT'    THEN 1
      ELSE 0
    END AS status_rank
  FROM part_files pf
  JOIN "print-farm"."ProjectThreeMFFile" f ON f."id" = pf.file_id
  JOIN chain c ON c.file_id = f."id"
  WHERE f."status" IN ('APPROVED', 'DRAFT')
)
-- 4) Per ogni (parte, variante) tieni il file preferito:
--    status_rank DESC (APPROVED>DRAFT), poi versione DESC, poi createdAt DESC.
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
  'Per (ProductPart, variante lineage) il file 3MF preferito (APPROVED>DRAFT). Multi-variante = piu'' righe per parte.';
