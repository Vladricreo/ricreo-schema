-- Bozze riallineate al piano (AUTO) con l'override operatore rimasto: la riga
-- riproponeva la vecchia scelta (es. bobina già montata al posto del piano).
-- Da ora il riallineo AUTO azzera l'override; qui si puliscono i residui.
UPDATE "print-farm"."SpoolSwapDraft"
SET override = NULL
WHERE "lastTouchedBy" = 'AUTO'
  AND override IS NOT NULL;
