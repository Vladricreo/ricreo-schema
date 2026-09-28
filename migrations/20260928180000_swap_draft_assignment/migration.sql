-- Lega la bozza swap/runout al job per cui è stata scritta. La rowKey è solo
-- stampante+slot: una scelta operatore restava attiva sui job successivi dello
-- stesso slot e teneva bloccate bobine che il piano voleva altrove.
ALTER TABLE "print-farm"."SpoolSwapDraft"
  ADD COLUMN "assignmentId" UUID;

-- Backfill: job aperto più recente della stampante già esistente al momento
-- dell'ultima modifica della bozza. Le bozze più vecchie di ogni job aperto
-- restano NULL e vengono trattate come residui di job precedenti.
UPDATE "print-farm"."SpoolSwapDraft" d
SET "assignmentId" = (
  SELECT a.id
  FROM "print-farm"."PrinterAssignment" a
  WHERE a."printerId" = d."printerId"
    AND a.status IN ('PRINTING', 'QUEUED', 'TO_HARVEST', 'START_FAILED', 'SCHEDULED')
    AND a."createdAt" <= d."updatedAt"
  ORDER BY a."createdAt" DESC
  LIMIT 1
)
WHERE d.state IN ('DRAFT', 'STALE');

-- Pulizia una tantum delle scelte operatore residue: senza job riconoscibile,
-- oppure STALE (il passaggio a STALE aggiorna updatedAt, quindi il backfill
-- non è affidabile per loro). Le bozze AUTO si rigenerano dal piano.
UPDATE "print-farm"."SpoolSwapDraft"
SET state = 'CANCELLED'
WHERE state IN ('DRAFT', 'STALE')
  AND "lastTouchedBy" IN ('UI', 'VOICE')
  AND ("assignmentId" IS NULL OR state = 'STALE');
