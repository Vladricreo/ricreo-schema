-- Lega la bozza swap/runout anche al ProductionJob (revisione 2026-09-30 V4b-1).
--
-- La bozza conosceva solo l'assignment (20260928180000_swap_draft_assignment),
-- ma lo scheduler riusa la stessa riga PrinterAssignment cambiandone il
-- productionJobId (generate-assignments ramo changedJob/reusable,
-- gantt-slice-apply). Una scelta operatore fatta per il job A restava "dello
-- stesso job" anche quando la riga rappresentava ormai il job B: TV, voce e
-- tab Preparazione mostravano la bobina scelta per A sul job B.
--
-- Nessun backfill: il job attuale dell'assignment NON è necessariamente quello
-- per cui la bozza è stata scritta (stesso errore del backfill 20260928180000).
-- NULL = ignoto: il codice ricade sul solo confronto per assignmentId e le
-- bozze AUTO si riscrivono con il job al primo generate.
--
-- Additiva e idempotente: il codice precedente ignora la colonna, quindi va
-- applicata PRIMA del deploy del client che la legge.
ALTER TABLE "print-farm"."SpoolSwapDraft"
  ADD COLUMN IF NOT EXISTS "productionJobId" UUID;
