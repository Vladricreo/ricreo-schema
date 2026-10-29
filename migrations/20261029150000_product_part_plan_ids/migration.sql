-- Piani parti con strategia "move": ProductPart.planIds (29/10).
--
-- Una nuova revisione del piano parti non clona più le parti che restano uguali:
-- le sposta nel nuovo piano (planId = revisione più recente) e ne aggiunge l'id a
-- planIds. Così la parte conserva giacenza, file 3MF, odette e BOM, e il piano
-- vecchio conserva la sua composizione per gli ordini congelati su di esso.
-- Le parti di un piano X sono: planId = X OR X = ANY(planIds).
--
-- Backfill:
--   • ogni parte contiene almeno il suo planId;
--   • una parte referenziata da righe d'ordine (ProductOrderProductPart) o di picking
--     (PickingLine) di ordini congelati su una revisione precedente è stata spostata
--     con la vecchia strategia "move" di Print Farm: appartiene a tutte le revisioni
--     del prodotto fra quella più vecchia che la usa e il suo planId (al 29/10 è un
--     solo caso, «Corpo principale» del supporto Alfa Romeo MiTo nero, ordine 683).
--
-- Idempotente: colonna con IF NOT EXISTS, backfill che unisce gli id senza duplicati.

ALTER TABLE "inventory"."ProductPart"
  ADD COLUMN IF NOT EXISTS "planIds" UUID[] NOT NULL DEFAULT ARRAY[]::UUID[];

COMMENT ON COLUMN "inventory"."ProductPart"."planIds"
  IS 'Tutte le revisioni del piano parti che contengono la parte (strategia move). planId = la più recente.';

WITH refs AS (
  SELECT r."productPartId" AS part_id, po."productPartPlanId" AS plan_id
  FROM "inventory"."ProductOrderProductPart" r
  JOIN "inventory"."ProductOrder" po ON po.id = r."productOrderId"
  WHERE po."productPartPlanId" IS NOT NULL
  UNION
  SELECT pl."productPartId", ao."productPartPlanId"
  FROM "inventory"."PickingLine" pl
  JOIN "inventory"."AssemblyOrder" ao ON ao.id = pl."assemblyOrderId"
  WHERE pl."productPartId" IS NOT NULL AND ao."productPartPlanId" IS NOT NULL
),
bounds AS (
  SELECT pp.id,
         pp."productId",
         cur."revisionNumber" AS cur_rev,
         LEAST(cur."revisionNumber", COALESCE(MIN(rp."revisionNumber"), cur."revisionNumber")) AS min_rev
  FROM "inventory"."ProductPart" pp
  JOIN "inventory"."ProductPartPlan" cur ON cur.id = pp."planId"
  LEFT JOIN refs ON refs.part_id = pp.id
  LEFT JOIN "inventory"."ProductPartPlan" rp
    ON rp.id = refs.plan_id AND rp."productId" = pp."productId"
  GROUP BY pp.id, pp."productId", cur."revisionNumber"
),
membership AS (
  SELECT b.id, ARRAY_AGG(DISTINCT pl.id) AS plan_ids
  FROM bounds b
  JOIN "inventory"."ProductPartPlan" pl
    ON pl."productId" = b."productId"
   AND pl."revisionNumber" BETWEEN b.min_rev AND b.cur_rev
  GROUP BY b.id
)
UPDATE "inventory"."ProductPart" pp
SET "planIds" = ARRAY(
  SELECT DISTINCT x FROM UNNEST(pp."planIds" || m.plan_ids) AS x ORDER BY x
)
FROM membership m
WHERE m.id = pp.id
  AND NOT (m.plan_ids <@ pp."planIds");
