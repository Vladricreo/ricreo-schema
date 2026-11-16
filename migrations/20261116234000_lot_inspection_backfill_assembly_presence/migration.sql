-- Controllo qualità dei lotti (R-245, 16/11/2026) — storico 4.
-- I lotti di produzione che hanno ricevuto pezzi e sono ancora senza controllo
-- (in gran parte parti stampate prima che lo scarico fosse legato ai movimenti)
-- ricevono un controllo attribuito all'operatore PIÙ PRESENTE in assemblaggio
-- [utente 16/11: «fai un backfill controllo qualita come fatto in base alle
-- attivita di assemblaggio, usa l'operatore piu presente»].
--
-- «Presenza» = numero di movimenti di assemblaggio (Movement con assemblyOrderId
-- e operatore). Cascata, dal criterio più preciso al più largo:
--   1. ordine di assemblaggio del lotto (InventoryLot.assemblyOrderId o ordini dei
--      suoi movimenti)
--   2. giorno del primo ingresso del lotto (ora di Roma)
--   3. settimana del primo ingresso
--   4. mese del primo ingresso
-- Parità: id utente più basso. inspectedAt = primo ingresso del lotto.
-- È un'attribuzione, non una registrazione diretta: le note lo dicono.
-- Idempotente: tocca solo lotti ancora senza nessun controllo.

WITH due AS (
  SELECT l.id,
         l."assemblyOrderId",
         r.total_in,
         (SELECT MIN(m.date) FROM "inventory"."Movement" m
           WHERE m."lotId" = l.id
             AND m.type IN ('PRODUZIONE', 'STAGE_IN', 'CORRECTION_UP', 'RESO_IN')) AS first_in
  FROM "inventory"."InventoryLot" l
  JOIN "inventory_views"."v_inventory_lot_remaining" r ON r.lot_id = l.id
  WHERE l."originType" = 'PRODUCTION'
    AND r.total_in > 0
    AND NOT EXISTS (SELECT 1 FROM "inventory"."LotInspection" i WHERE i."lotId" = l.id)
),
asm AS (
  SELECT m."byUserId" AS uid,
         m."assemblyOrderId" AS ao,
         (m.date AT TIME ZONE 'Europe/Rome') AS ts
  FROM "inventory"."Movement" m
  WHERE m."assemblyOrderId" IS NOT NULL
    AND m."byUserId" IS NOT NULL
),
pick AS (
  SELECT d.id, d."assemblyOrderId", d.total_in, d.first_in,
    COALESCE(
      (SELECT json_build_object('uid', a.uid, 'how', 'order') FROM asm a
        WHERE a.ao = d."assemblyOrderId"
           OR a.ao IN (SELECT m2."assemblyOrderId" FROM "inventory"."Movement" m2
                        WHERE m2."lotId" = d.id AND m2."assemblyOrderId" IS NOT NULL)
        GROUP BY a.uid ORDER BY COUNT(*) DESC, a.uid LIMIT 1),
      (SELECT json_build_object('uid', a.uid, 'how', 'day') FROM asm a
        WHERE a.ts::date = (d.first_in AT TIME ZONE 'Europe/Rome')::date
        GROUP BY a.uid ORDER BY COUNT(*) DESC, a.uid LIMIT 1),
      (SELECT json_build_object('uid', a.uid, 'how', 'week') FROM asm a
        WHERE date_trunc('week', a.ts) = date_trunc('week', d.first_in AT TIME ZONE 'Europe/Rome')
        GROUP BY a.uid ORDER BY COUNT(*) DESC, a.uid LIMIT 1),
      (SELECT json_build_object('uid', a.uid, 'how', 'month') FROM asm a
        WHERE date_trunc('month', a.ts) = date_trunc('month', d.first_in AT TIME ZONE 'Europe/Rome')
        GROUP BY a.uid ORDER BY COUNT(*) DESC, a.uid LIMIT 1)
    ) AS p
  FROM due d
  WHERE d.first_in IS NOT NULL
)
INSERT INTO "inventory"."LotInspection" (
  "id", "lotId", "inspectedAt", "inspectedBy", "result", "notes", "source",
  "quantityChecked", "assemblyOrderId", "createdAt", "updatedAt"
)
SELECT gen_random_uuid(),
       pk.id,
       pk.first_in,
       (pk.p->>'uid')::int,
       'PASSED'::"inventory"."LotInspectionResult",
       format(
         'Ricostruito il 16/11/2026 per attribuzione: nessuna registrazione diretta del controllo. Operatore = il più presente in assemblaggio %s (più movimenti di assemblaggio). %s pezzi entrati nel lotto.',
         CASE pk.p->>'how'
           WHEN 'order' THEN 'sull''ordine del lotto'
           WHEN 'day' THEN 'il ' || to_char(pk.first_in AT TIME ZONE 'Europe/Rome', 'DD/MM/YYYY')
           WHEN 'week' THEN 'nella settimana del ' || to_char(pk.first_in AT TIME ZONE 'Europe/Rome', 'DD/MM/YYYY')
           ELSE 'nel mese di ' || to_char(pk.first_in AT TIME ZONE 'Europe/Rome', 'MM/YYYY')
         END,
         pk.total_in
       ),
       'ASSEMBLY_BACKFILL'::"inventory"."LotInspectionSource",
       pk.total_in,
       pk."assemblyOrderId",
       now(),
       now()
FROM pick pk
WHERE pk.p IS NOT NULL;
