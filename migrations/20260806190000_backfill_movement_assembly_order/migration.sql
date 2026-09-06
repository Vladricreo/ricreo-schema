-- Collega all'ordine di assemblaggio i movimenti di consumo che ne fanno parte.
--
-- Perché serve: il consumo di parti da odette (`consumeFromOdetteFIFO`) copiava
-- l'ordine dalla riga di contenuto, che per le parti porta `productOrderId` (chi le
-- ha prodotte) e non `assemblyOrderId` (chi le consuma). Risultato: nella pagina
-- movimenti le righe `USO` delle parti comparivano senza ordine, mentre i movimenti
-- di WIP della stessa operazione mostravano l'ordine corretto.
--
-- Il codice ora passa l'ordine esplicitamente; qui si sistemano le righe già scritte
-- usando il diario operazione, che è l'unico collegamento certo (niente euristiche
-- su date o fasi). I movimenti di operazioni non registrate nel diario restano senza
-- ordine: non c'è modo affidabile di ricostruirlo a posteriori.
--
-- Sicuro da rieseguire: aggiorna solo le righe ancora senza ordine, e il trigger
-- `after_movement_insert` è AFTER INSERT, quindi un UPDATE non ricalcola le giacenze.

UPDATE "inventory"."Movement" AS m
SET "assemblyOrderId" = j."assemblyOrderId"
FROM "inventory"."AssemblyJournalEntry" AS j
WHERE m."journalEntryId" = j."id"
  AND m."assemblyOrderId" IS NULL;
