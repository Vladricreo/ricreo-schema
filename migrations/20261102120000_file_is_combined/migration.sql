-- Piatti combinati (S-188): flag `isCombined` sul file, tenuto aggiornato da un
-- trigger su ProjectPart, così vale con qualunque scrittore (upload, versioni,
-- modifica file, mappa oggetti, slicer, altre app sul DB condiviso).
-- Combinato = righe ProjectPart del file con almeno due productPartId diversi
-- (stessa regola di `isCombinedFileParts` e della vista sotto).

ALTER TABLE "print-farm"."ProjectThreeMFFile" ADD COLUMN "isCombined" BOOLEAN NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION "print-farm".pf_refresh_file_is_combined(p_file_id uuid)
RETURNS void
LANGUAGE sql
AS $$
  UPDATE "print-farm"."ProjectThreeMFFile" f
  SET "isCombined" = c.v
  FROM (
    SELECT (
      SELECT count(DISTINCT pp."productPartId")
      FROM "print-farm"."ProjectPart" pp
      WHERE pp."fileId" = p_file_id AND pp."productPartId" IS NOT NULL
    ) > 1 AS v
  ) c
  WHERE f.id = p_file_id AND f."isCombined" IS DISTINCT FROM c.v;
$$;

CREATE OR REPLACE FUNCTION "print-farm".pf_project_part_is_combined_trg()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    PERFORM "print-farm".pf_refresh_file_is_combined(NEW."fileId");
  END IF;
  IF TG_OP = 'DELETE' OR (TG_OP = 'UPDATE' AND OLD."fileId" IS DISTINCT FROM NEW."fileId") THEN
    PERFORM "print-farm".pf_refresh_file_is_combined(OLD."fileId");
  END IF;
  RETURN NULL;
END;
$$;

CREATE TRIGGER "ProjectPart_is_combined"
AFTER INSERT OR DELETE OR UPDATE OF "fileId", "productPartId" ON "print-farm"."ProjectPart"
FOR EACH ROW EXECUTE FUNCTION "print-farm".pf_project_part_is_combined_trg();

-- Backfill dei file esistenti.
UPDATE "print-farm"."ProjectThreeMFFile" f
SET "isCombined" = true
WHERE f.id IN (
  SELECT pp."fileId"
  FROM "print-farm"."ProjectPart" pp
  WHERE pp."productPartId" IS NOT NULL
  GROUP BY pp."fileId"
  HAVING count(DISTINCT pp."productPartId") > 1
);

-- Vista dei file preferiti per parte: esclude i combinati con la colonna invece
-- della CTE `combined_files` (stesse colonne e stesso risultato).
CREATE OR REPLACE VIEW print_farm_views.v_pf_part_preferred_files AS
 WITH RECURSIVE chain AS (
         SELECT f.id AS file_id,
            f."previousVersionId" AS prev_id,
            f.id AS root_id
           FROM "print-farm"."ProjectThreeMFFile" f
          WHERE f."previousVersionId" IS NULL
        UNION ALL
         SELECT f.id AS file_id,
            f."previousVersionId" AS prev_id,
            c.root_id
           FROM "print-farm"."ProjectThreeMFFile" f
             JOIN chain c ON f."previousVersionId" = c.file_id
        ), part_files AS (
         SELECT f.id AS file_id,
            f."productPartId" AS part_id
           FROM "print-farm"."ProjectThreeMFFile" f
          WHERE f."productPartId" IS NOT NULL
        UNION
         SELECT pp."fileId" AS file_id,
            pp."productPartId" AS part_id
           FROM "print-farm"."ProjectPart" pp
          WHERE pp."productPartId" IS NOT NULL
        ), candidates AS (
         SELECT pf.part_id,
            c.root_id,
            f.id AS file_id,
            f.version,
            f.status::text AS status,
            f."partCount" AS part_count,
            f."compatiblePrinters" AS compatible_printers,
            f."estimatedDurationMinutes" AS estimated_minutes,
            f."createdAt" AS created_at,
                CASE f.status
                    WHEN 'APPROVED'::"print-farm"."FileStatus" THEN 2
                    WHEN 'DRAFT'::"print-farm"."FileStatus" THEN 1
                    ELSE 0
                END AS status_rank
           FROM part_files pf
             JOIN "print-farm"."ProjectThreeMFFile" f ON f.id = pf.file_id
             JOIN chain c ON c.file_id = f.id
          WHERE (f.status = ANY (ARRAY['APPROVED'::"print-farm"."FileStatus", 'DRAFT'::"print-farm"."FileStatus"])) AND NOT f."isCombined"
        )
 SELECT DISTINCT ON (part_id, root_id) part_id AS "productPartId",
    root_id AS "variantRootId",
    file_id AS "fileId",
    version,
    status,
        CASE
            WHEN status_rank = 2 THEN 'approved'::text
            ELSE 'draft'::text
        END AS selection,
    part_count AS "partCount",
    compatible_printers AS "compatiblePrinters",
    estimated_minutes AS "estimatedDurationMinutes"
   FROM candidates
  ORDER BY part_id, root_id, status_rank DESC, version DESC, created_at DESC;
