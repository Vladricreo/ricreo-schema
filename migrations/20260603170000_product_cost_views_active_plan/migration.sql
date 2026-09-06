-- Aggiorna v_product_cost_breakdown per leggere SOLO le parti del piano ATTIVO.
--
-- Dopo l'introduzione di ProductPartPlan un prodotto può avere parti appartenenti a piani
-- esauriti (storici) oltre a quelle del piano attivo. Senza filtro, il costo materie prime e
-- il costo parti BUY verrebbero sommati su tutti i piani (doppio conteggio). Filtriamo le
-- parti al piano con status = 'ACTIVE'.

CREATE OR REPLACE VIEW inventory_views.v_product_cost_breakdown AS
WITH material_cost AS (
    SELECT
        pp."productId" AS product_id,
        SUM(
            pp."quantityNeeded"::NUMERIC
            * mb."usedWeight"::NUMERIC
            * CASE
                WHEN (COALESCE(i.weight, sw.weight, 0)::NUMERIC * 1000) > 0
                  THEN (i.price::NUMERIC / (COALESCE(i.weight, sw.weight, 0)::NUMERIC * 1000))
                ELSE 0
              END
        ) AS materials_cost
    FROM inventory."ProductPart" pp
    JOIN inventory."ProductPartPlan" ap
      ON ap.id = pp."planId" AND ap.status = 'ACTIVE'
    JOIN inventory."ProductPartMaterial" mb
      ON mb."productPartId" = pp.id AND mb.priority = 0
    JOIN inventory_views.v_item_spec_resolved ri
      ON ri.spec_id = mb."materialSpecId"
    JOIN inventory."Item" i ON i.id = ri.item_id
    LEFT JOIN inventory."StandardWeight" sw ON sw.id = i."standardWeightId"
    WHERE pp."sourceType" = 'MAKE'
    GROUP BY pp."productId"
),
buy_parts_cost AS (
    SELECT
        pp."productId" AS product_id,
        SUM(COALESCE(pp.price, 0)::NUMERIC * pp."quantityNeeded"::NUMERIC) AS buy_parts_cost
    FROM inventory."ProductPart" pp
    JOIN inventory."ProductPartPlan" ap
      ON ap.id = pp."planId" AND ap.status = 'ACTIVE'
    WHERE pp."sourceType" = 'BUY'
    GROUP BY pp."productId"
),
component_cost AS (
    SELECT
        c."productId" AS product_id,
        SUM(COALESCE(i.price, 0)::NUMERIC * c.quantity::NUMERIC) AS components_cost
    FROM inventory."ProductToComponent" c
    JOIN inventory_views.v_item_spec_resolved ri ON ri.spec_id = c."itemSpecId"
    JOIN inventory."Item" i ON i.id = ri.item_id
    WHERE c.priority = 0
    GROUP BY c."productId"
),
packaging_cost AS (
    SELECT
        p."productId" AS product_id,
        SUM(COALESCE(i.price, 0)::NUMERIC * p.quantity::NUMERIC) AS packaging_cost
    FROM inventory."ProductToPackage" p
    JOIN inventory_views.v_item_spec_resolved ri ON ri.spec_id = p."itemSpecId"
    JOIN inventory."Item" i ON i.id = ri.item_id
    WHERE p.priority = 0
    GROUP BY p."productId"
),
utility_cost AS (
    SELECT
        u."productId" AS product_id,
        SUM(COALESCE(i.price, 0)::NUMERIC * u.quantity::NUMERIC) AS utilities_cost
    FROM inventory."ProductToUtility" u
    JOIN inventory_views.v_item_spec_resolved ri ON ri.spec_id = u."itemSpecId"
    JOIN inventory."Item" i ON i.id = ri.item_id
    WHERE u.priority = 0
    GROUP BY u."productId"
)
SELECT
    pr.id AS product_id,
    COALESCE(mc.materials_cost, 0)::DECIMAL(12,4) AS materials_cost,
    COALESCE(bp.buy_parts_cost, 0)::DECIMAL(12,4) AS buy_parts_cost,
    COALESCE(cc.components_cost, 0)::DECIMAL(12,4) AS components_cost,
    COALESCE(pc.packaging_cost, 0)::DECIMAL(12,4) AS packaging_cost,
    COALESCE(uc.utilities_cost, 0)::DECIMAL(12,4) AS utilities_cost,
    (
        COALESCE(mc.materials_cost, 0)
      + COALESCE(bp.buy_parts_cost, 0)
      + COALESCE(cc.components_cost, 0)
      + COALESCE(pc.packaging_cost, 0)
      + COALESCE(uc.utilities_cost, 0)
    )::DECIMAL(12,4) AS raw_material_cost
FROM inventory."Product" pr
LEFT JOIN material_cost mc ON mc.product_id = pr.id
LEFT JOIN buy_parts_cost bp ON bp.product_id = pr.id
LEFT JOIN component_cost cc ON cc.product_id = pr.id
LEFT JOIN packaging_cost pc ON pc.product_id = pr.id
LEFT JOIN utility_cost uc ON uc.product_id = pr.id;
