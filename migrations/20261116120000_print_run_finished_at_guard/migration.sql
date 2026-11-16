-- S-302 (16/11): una PrintRun chiusa (COMPLETED o FAILED) deve avere finishedAt.
--
-- 9 run COMPLETED fra il 04/09 e il 02/10 sono rimaste senza finishedAt (scarico
-- di allora, prima di S-131). Chi leggeva COALESCE(finishedAt, now()) le contava
-- come stampa continua da settembre: utilizzo dei pool gonfiato di 8-16 punti in
-- «Quante stampanti servono».
--
-- 1. Bonifica delle 9 run, solo per id e solo se finishedAt è ancora NULL:
--    fine = la prima fra inizio + durata (reale, altrimenti stimata dal file),
--    primo scarico della run, inizio della run successiva sulla stessa stampante.
-- 2. Trigger di protezione: se una run diventa (o nasce) COMPLETED/FAILED senza
--    finishedAt, lo riempie invece di bloccare la scrittura (un CHECK farebbe
--    fallire lo scarico in corso). Fine = inizio + durata reale se nota e già
--    passata, altrimenti adesso. Non tocca le run che hanno già finishedAt né
--    le riaperture a IN_PROGRESS (self-heal, ripresa dopo FAILED).

-- 1. Bonifica -----------------------------------------------------------------
UPDATE "print-farm"."PrintRun" r
SET "finishedAt" = fix.finished_at,
    "updatedAt" = now(),
    notes = concat_ws(E'\n', NULLIF(r.notes, ''),
      '[S-302 16/11] finishedAt mancante ricostruito (inizio + durata, scarico o run successiva)')
FROM (
  SELECT
    r2.id,
    LEAST(
      r2."startedAt" + COALESCE(r2."printTimeMinutes", f."estimatedDurationMinutes"::NUMERIC, 0) * INTERVAL '1 minute',
      COALESCE(
        (SELECT MIN(h."harvestedAt") FROM "print-farm"."PrinterHarvest" h WHERE h."printRunId" = r2.id),
        'infinity'::TIMESTAMPTZ
      ),
      COALESCE(
        (SELECT MIN(n."startedAt") FROM "print-farm"."PrintRun" n
          WHERE n."printerId" = r2."printerId" AND n."startedAt" > r2."startedAt"),
        'infinity'::TIMESTAMPTZ
      )
    ) AS finished_at
  FROM "print-farm"."PrintRun" r2
  LEFT JOIN "print-farm"."ProjectThreeMFFile" f ON f.id = r2."fileId"
  WHERE r2.id IN (
    '7e91c598-8990-48ae-b757-dc001f2a936b',
    '568218d3-8922-4f53-9202-7c7d24cf81ab',
    '1b763d5d-6975-457d-a915-f1bbe6cd1b94',
    '98f7bcdb-e7af-46cb-9568-9f824a70c610',
    '39fa890c-16aa-4f0c-a934-76e6c121d33e',
    'f24d8b46-35ea-4e15-93bd-a286040fe13f',
    '02ae4ed9-2268-4f59-b991-83d1ddc66fe2',
    'ace98a5d-ee24-455b-90ba-14f004a9b8b4',
    'b35028b8-509d-4974-ba21-c8351766f62c'
  )
    AND r2."finishedAt" IS NULL
    AND r2."startedAt" IS NOT NULL
) fix
WHERE r.id = fix.id
  AND r."finishedAt" IS NULL;

-- 2. Trigger di protezione -----------------------------------------------------
CREATE OR REPLACE FUNCTION "print-farm".pf_print_run_fill_finished_at_trg()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.status::TEXT IN ('COMPLETED', 'FAILED') AND NEW."finishedAt" IS NULL THEN
    NEW."finishedAt" := CASE
      WHEN NEW."startedAt" IS NOT NULL
        AND NEW."printTimeMinutes" IS NOT NULL
        AND NEW."printTimeMinutes" > 0
        AND NEW."startedAt" + NEW."printTimeMinutes" * INTERVAL '1 minute' <= now()
        THEN NEW."startedAt" + NEW."printTimeMinutes" * INTERVAL '1 minute'
      ELSE now()
    END;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS "PrintRun_fill_finished_at" ON "print-farm"."PrintRun";
CREATE TRIGGER "PrintRun_fill_finished_at"
BEFORE INSERT OR UPDATE OF status, "finishedAt" ON "print-farm"."PrintRun"
FOR EACH ROW
EXECUTE FUNCTION "print-farm".pf_print_run_fill_finished_at_trg();

COMMENT ON FUNCTION "print-farm".pf_print_run_fill_finished_at_trg() IS
  'S-302: una PrintRun COMPLETED/FAILED senza finishedAt riceve inizio + durata reale (se già passata) o adesso.';
