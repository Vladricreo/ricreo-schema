-- Riordino: velocità su giorni di calendario (zeri inclusi, blend 75% finestra /
-- 25% ultimi 7gg) e stagionalità anno su anno (neutra senza 12 mesi di storico).
-- Sostituisce la media pesata sui soli bucket con consumo e il fattore mensile
-- calcolato sul mese corrente parziale (dimezzava i consumi a inizio mese).
-- Fonte: prisma/custom_migrations/sql/consumption_demand_views.sql

-- ============================================================================
-- CONSUMPTION DEMAND VIEWS
-- Consumo ponderato (allineato a inventory-orders-calculations.ts), domanda
-- da ordini produzione attivi, da assemblaggi pendenti (BOM prodotto),
-- fattore stagionalità anno su anno per categoria (neutro senza 12 mesi di storico).
-- ============================================================================


-- ============================================================================
-- Parametri: giorni finestra da Settings STOCK_THRESHOLD (default 30)
-- ============================================================================
-- (Usato solo nei commenti; la logica è inline nella view item.)

-- ============================================================================
-- VIEW: v_item_consumption_demand — una riga per Item
-- Domanda produzione: come la view spec, C/P/U solo da ProductOrder NON legati
-- a un AssemblyOrder (altrimenti lo stesso fabbisogno è già in demand_from_assembly).
-- I materiali restano sempre (non sono nella BOM assemblaggio).
-- SKU «non stoccare» / usati: la domanda BOM viene riassegnata allo SKU acquistabile
-- della stessa ItemSpec (preferito se buyable, altrimenti specPriority).
-- ============================================================================
CREATE OR REPLACE VIEW inventory_views.v_item_consumption_demand AS
WITH params AS (
    SELECT GREATEST(
        COALESCE(
            (
                SELECT
                    CASE
                        WHEN s.value IS NULL THEN 30
                        WHEN jsonb_typeof(s.value::jsonb) = 'number' THEN (s.value::text)::INT
                        WHEN (s.value::jsonb) ? 'days' THEN (s.value::jsonb->>'days')::INT
                        WHEN s.value::text ~ '^[0-9]+$' THEN s.value::text::INT
                        ELSE 30
                    END
                FROM inventory."Settings" s
                WHERE s.name = 'STOCK_THRESHOLD'
                LIMIT 1
            ),
            30
        ),
        1
    ) AS threshold_days
),
per_item_movements AS (
    SELECT
        m."itemId" AS item_id,
        m.quantity,
        m.date,
        (CURRENT_DATE - (m.date AT TIME ZONE 'UTC')::DATE)::INT AS days_ago
    FROM inventory."Movement" m
    CROSS JOIN params p
    WHERE m."itemId" IS NOT NULL
      -- TRASH incluso: lo scarto riduce stock utilizzabile e va coperto dal riordino.
      AND m.type IN ('USO', 'VENDITA', 'TRASH')
      AND m.date >= CURRENT_TIMESTAMP - (p.threshold_days::TEXT || ' days')::INTERVAL
),
-- Primo consumo in assoluto: se precede la finestra, la finestra è osservata
-- per intero (i giorni a zero contano). Altrimenti si osserva dal primo uso.
first_use AS (
    SELECT m."itemId" AS item_id, MIN((m.date AT TIME ZONE 'UTC')::DATE) AS first_day
    FROM inventory."Movement" m
    WHERE m."itemId" IS NOT NULL
      AND m.type IN ('USO', 'VENDITA', 'TRASH')
    GROUP BY m."itemId"
),
bucket_sums AS (
    SELECT
        pm.item_id,
        SUM(CASE WHEN pm.days_ago >= 0 AND pm.days_ago < 7 THEN pm.quantity ELSE 0 END)::NUMERIC AS s_recent,
        COUNT(*)::INT AS movement_count,
        SUM(pm.quantity)::BIGINT AS total_consumption,
        (CURRENT_DATE - MIN((pm.date AT TIME ZONE 'UTC')::DATE) + 1)::INT AS oldest_age_days
    FROM per_item_movements pm
    GROUP BY pm.item_id
),
-- Velocità su giorni di calendario (zeri inclusi), non sui soli periodi con consumo:
-- un picco isolato non viene più moltiplicato e un articolo fermo rallenta davvero.
-- Blend 75% finestra intera + 25% ultimi 7 giorni.
weighted_raw AS (
    SELECT
        bs.item_id,
        bs.movement_count,
        bs.total_consumption,
        bs.oldest_age_days,
        bs.s_recent,
        GREATEST(
            7,
            LEAST(p.threshold_days, CURRENT_DATE - fu.first_day + 1)
        )::INT AS obs_days,
        (
            bs.total_consumption > 0
            AND bs.oldest_age_days >= 7
            AND bs.movement_count >= 3
        ) AS is_reliable
    FROM bucket_sums bs
    CROSS JOIN params p
    JOIN first_use fu ON fu.item_id = bs.item_id
),
weighted_calc AS (
    SELECT
        wr.item_id,
        wr.movement_count,
        wr.total_consumption,
        wr.obs_days AS effective_days,
        CASE
            WHEN wr.total_consumption <= 0 THEN 0::NUMERIC
            ELSE wr.total_consumption::NUMERIC / wr.obs_days
        END AS daily_consumption_simple,
        wr.is_reliable,
        CASE
            WHEN wr.is_reliable AND wr.total_consumption > 0 THEN
                0.75 * (wr.total_consumption::NUMERIC / wr.obs_days)
              + 0.25 * (wr.s_recent / LEAST(7, wr.obs_days))
            ELSE 0::NUMERIC
        END AS daily_consumption_weighted
    FROM weighted_raw wr
),
pending_assembly AS (
    SELECT
        ao.id,
        ao."productId" AS product_id,
        ao."skuId" AS sku_id,
        GREATEST(ao."quantityToAssemble" - ao."quantityAssembled", 0)::NUMERIC AS remain
    FROM inventory."AssemblyOrder" ao
    WHERE ao.status NOT IN ('ASSEMBLY_COMPLETED', 'CANCELLED')
      AND GREATEST(ao."quantityToAssemble" - ao."quantityAssembled", 0) > 0
),
assembly_lines AS (
    SELECT ri.item_id, SUM(c.quantity * pa.remain)::NUMERIC AS qty
    FROM pending_assembly pa
    JOIN inventory."ProductToComponent" c
      ON c."productId" = pa.product_id
     AND c.priority = 0
     AND (c."skuId" IS NULL OR c."skuId" = pa.sku_id)
    JOIN inventory_views.v_item_spec_resolved ri ON ri.spec_id = c."itemSpecId"
    GROUP BY ri.item_id
    UNION ALL
    SELECT ri.item_id, SUM(p.quantity * pa.remain)::NUMERIC AS qty
    FROM pending_assembly pa
    JOIN inventory."ProductToPackage" p
      ON p."productId" = pa.product_id
     AND p.priority = 0
     AND (p."skuId" IS NULL OR p."skuId" = pa.sku_id)
    JOIN inventory_views.v_item_spec_resolved ri ON ri.spec_id = p."itemSpecId"
    GROUP BY ri.item_id
    UNION ALL
    SELECT ri.item_id, SUM(u.quantity * pa.remain)::NUMERIC AS qty
    FROM pending_assembly pa
    JOIN inventory."ProductToUtility" u
      ON u."productId" = pa.product_id
     AND u.priority = 0
     AND (u."skuId" IS NULL OR u."skuId" = pa.sku_id)
    JOIN inventory_views.v_item_spec_resolved ri ON ri.spec_id = u."itemSpecId"
    GROUP BY ri.item_id
),
assembly_demand_by_item AS (
    SELECT item_id, SUM(qty)::NUMERIC AS demand_qty
    FROM assembly_lines
    GROUP BY item_id
),
-- Allineata a v_item_spec_consumption_demand: niente doppio conteggio
-- assembly + ProductOrder collegato allo stesso AssemblyOrder.
production_demand_by_item AS (
    SELECT
        r.item_id,
        SUM(
            CASE
                WHEN r.kind = 'Material' THEN
                    CASE
                        WHEN (COALESCE(i.weight, sw.weight, 0)::NUMERIC * 1000) > 0 THEN
                            CEIL(
                                r.quantity_needed_remaining
                                / (COALESCE(i.weight, sw.weight, 0)::NUMERIC * 1000)
                            )
                        ELSE 0
                    END
                ELSE r.quantity_needed_remaining
            END
        )::INT AS demand_qty
    FROM inventory_views.v_product_order_required_items r
    JOIN inventory."ProductOrder" o ON o.id = r.product_order_id
    JOIN inventory."Item" i ON i.id = r.item_id
    LEFT JOIN inventory."StandardWeight" sw ON sw.id = i."standardWeightId"
    WHERE o."productionStatus" IN ('READY_TO_PRODUCE', 'PRODUCING', 'NEED_SUPPLIES')
      AND (r.kind <> 'Material' OR r.bom_priority = 0)
      AND (r.kind = 'Material' OR r.assembly_order_id IS NULL)
    GROUP BY r.item_id
),
-- SKU acquistabile della famiglia (preferito se buyable, altrimenti specPriority).
family_buy_target AS (
    SELECT DISTINCT ON (i."itemSpecId")
        i."itemSpecId" AS spec_id,
        i.id AS item_id
    FROM inventory."Item" i
    LEFT JOIN inventory_views.v_item_spec_stock_position pos
      ON pos.spec_id = i."itemSpecId"
    WHERE i."itemSpecId" IS NOT NULL
      AND COALESCE(i."isUsed", false) = false
      AND COALESCE((i.properties->>'reorderDisabled')::boolean, false) = false
      AND COALESCE((i.properties->>'supplierOutOfStock')::boolean, false) = false
    ORDER BY
        i."itemSpecId",
        CASE
            WHEN pos.preferred_item_id IS NOT NULL AND i.id = pos.preferred_item_id
            THEN 0 ELSE 1
        END,
        i."specPriority" ASC,
        i.name ASC,
        i.id ASC
),
-- Domanda BOM di SKU «non stoccare»/usati → buy target della stessa famiglia.
production_demand_remapped AS (
    SELECT
        COALESCE(bt.item_id, pd.item_id) AS item_id,
        SUM(pd.demand_qty)::INT AS demand_qty
    FROM production_demand_by_item pd
    JOIN inventory."Item" src ON src.id = pd.item_id
    LEFT JOIN family_buy_target bt
      ON src."itemSpecId" IS NOT NULL
     AND (
            COALESCE((src.properties->>'reorderDisabled')::boolean, false) = true
         OR COALESCE(src."isUsed", false) = true
     )
     AND bt.spec_id = src."itemSpecId"
    GROUP BY COALESCE(bt.item_id, pd.item_id)
),
assembly_demand_remapped AS (
    SELECT
        COALESCE(bt.item_id, ad.item_id) AS item_id,
        SUM(ad.demand_qty)::NUMERIC AS demand_qty
    FROM assembly_demand_by_item ad
    JOIN inventory."Item" src ON src.id = ad.item_id
    LEFT JOIN family_buy_target bt
      ON src."itemSpecId" IS NOT NULL
     AND (
            COALESCE((src.properties->>'reorderDisabled')::boolean, false) = true
         OR COALESCE(src."isUsed", false) = true
     )
     AND bt.spec_id = src."itemSpecId"
    GROUP BY COALESCE(bt.item_id, ad.item_id)
),
category_seasonal AS (
    -- Stagionalità anno su anno: consumo della categoria nei prossimi N giorni
    -- dell'anno scorso / consumo nei N giorni precedenti (N = finestra soglia).
    -- Neutra (1) finché la categoria non ha almeno un anno + N giorni di storico:
    -- niente mesi parziali né medie su "giorni con dati".
    SELECT
        COALESCE(c.name, 'Senza categoria') AS category_name,
        CASE
            WHEN MIN((m.date AT TIME ZONE 'UTC')::DATE) <= CURRENT_DATE - 365 - p.threshold_days
             AND SUM(CASE
                    WHEN (m.date AT TIME ZONE 'UTC')::DATE >= CURRENT_DATE - 365 - p.threshold_days
                     AND (m.date AT TIME ZONE 'UTC')::DATE < CURRENT_DATE - 365
                    THEN m.quantity ELSE 0 END) > 0
            THEN LEAST(
                2::NUMERIC,
                GREATEST(
                    0.5::NUMERIC,
                    SUM(CASE
                        WHEN (m.date AT TIME ZONE 'UTC')::DATE >= CURRENT_DATE - 365
                         AND (m.date AT TIME ZONE 'UTC')::DATE < CURRENT_DATE - 365 + p.threshold_days
                        THEN m.quantity ELSE 0 END)::NUMERIC
                    / SUM(CASE
                        WHEN (m.date AT TIME ZONE 'UTC')::DATE >= CURRENT_DATE - 365 - p.threshold_days
                         AND (m.date AT TIME ZONE 'UTC')::DATE < CURRENT_DATE - 365
                        THEN m.quantity ELSE 0 END)::NUMERIC
                )
            )
            ELSE 1::NUMERIC
        END AS seasonal_factor
    FROM inventory."Movement" m
    JOIN inventory."Item" i ON i.id = m."itemId"
    LEFT JOIN inventory."Category" c ON c.id = i."categoryId"
    CROSS JOIN params p
    WHERE m.type IN ('USO', 'VENDITA', 'TRASH')
      AND i.type <> 'TOOL'
    GROUP BY COALESCE(c.name, 'Senza categoria'), p.threshold_days
),
item_category AS (
    SELECT
        i.id AS item_id,
        COALESCE(c.name, 'Senza categoria') AS category_name
    FROM inventory."Item" i
    LEFT JOIN inventory."Category" c ON c.id = i."categoryId"
),
seasonal AS (
    SELECT ic.item_id, COALESCE(cs.seasonal_factor, 1::NUMERIC) AS seasonal_factor
    FROM item_category ic
    LEFT JOIN category_seasonal cs ON cs.category_name = ic.category_name
)
SELECT
    i.id AS item_id,
    COALESCE(wc.daily_consumption_weighted, 0)::NUMERIC(14, 6) AS daily_consumption_weighted,
    COALESCE(wc.daily_consumption_simple, 0)::NUMERIC(14, 6) AS daily_consumption_simple,
    COALESCE(wc.is_reliable, FALSE) AS is_reliable,
    COALESCE(wc.movement_count, 0) AS movement_count,
    COALESCE(wc.effective_days, 0) AS effective_days,
    COALESCE(wc.total_consumption, 0)::BIGINT AS total_consumption,
    COALESCE(pd.demand_qty, 0)::INT AS demand_from_production,
    COALESCE(CEIL(ad.demand_qty), 0)::INT AS demand_from_assembly,
    COALESCE(se.seasonal_factor, 1::NUMERIC)::NUMERIC(8, 4) AS seasonal_factor,
    (
        COALESCE(wc.daily_consumption_weighted, 0::NUMERIC)
        * COALESCE(se.seasonal_factor, 1::NUMERIC)
    )::NUMERIC(14, 6) AS adjusted_daily_consumption
FROM inventory."Item" i
LEFT JOIN weighted_calc wc ON wc.item_id = i.id
LEFT JOIN production_demand_remapped pd ON pd.item_id = i.id
LEFT JOIN assembly_demand_remapped ad ON ad.item_id = i.id
LEFT JOIN seasonal se ON se.item_id = i.id;

-- ============================================================================
-- VIEW: v_product_part_consumption_demand — una riga per ProductPart BUY
-- ============================================================================
CREATE OR REPLACE VIEW inventory_views.v_product_part_consumption_demand AS
WITH params AS (
    SELECT GREATEST(
        COALESCE(
            (
                SELECT
                    CASE
                        WHEN s.value IS NULL THEN 30
                        WHEN jsonb_typeof(s.value::jsonb) = 'number' THEN (s.value::text)::INT
                        WHEN (s.value::jsonb) ? 'days' THEN (s.value::jsonb->>'days')::INT
                        WHEN s.value::text ~ '^[0-9]+$' THEN s.value::text::INT
                        ELSE 30
                    END
                FROM inventory."Settings" s
                WHERE s.name = 'STOCK_THRESHOLD'
                LIMIT 1
            ),
            30
        ),
        1
    ) AS threshold_days
),
buy_parts AS (
    SELECT pp.id AS product_part_id, pp."productId" AS product_id
    FROM inventory."ProductPart" pp
    WHERE pp."sourceType" = 'BUY'
),
per_part_movements AS (
    SELECT
        m."productPartId" AS product_part_id,
        m.quantity,
        m.date,
        (CURRENT_DATE - (m.date AT TIME ZONE 'UTC')::DATE)::INT AS days_ago
    FROM inventory."Movement" m
    INNER JOIN buy_parts bp ON bp.product_part_id = m."productPartId"
    CROSS JOIN params p
    WHERE m."productPartId" IS NOT NULL
      -- TRASH incluso: lo scarto riduce stock utilizzabile e va coperto dal riordino.
      AND m.type IN ('USO', 'VENDITA', 'TRASH')
      AND m.date >= CURRENT_TIMESTAMP - (p.threshold_days::TEXT || ' days')::INTERVAL
),
first_use AS (
    SELECT m."productPartId" AS product_part_id, MIN((m.date AT TIME ZONE 'UTC')::DATE) AS first_day
    FROM inventory."Movement" m
    WHERE m."productPartId" IS NOT NULL
      AND m.type IN ('USO', 'VENDITA', 'TRASH')
    GROUP BY m."productPartId"
),
bucket_sums AS (
    SELECT
        pm.product_part_id,
        SUM(CASE WHEN pm.days_ago >= 0 AND pm.days_ago < 7 THEN pm.quantity ELSE 0 END)::NUMERIC AS s_recent,
        COUNT(*)::INT AS movement_count,
        SUM(pm.quantity)::BIGINT AS total_consumption,
        (CURRENT_DATE - MIN((pm.date AT TIME ZONE 'UTC')::DATE) + 1)::INT AS oldest_age_days
    FROM per_part_movements pm
    GROUP BY pm.product_part_id
),
-- Stessa velocità su calendario di v_item_consumption_demand.
weighted_raw AS (
    SELECT
        bs.product_part_id,
        bs.movement_count,
        bs.total_consumption,
        bs.oldest_age_days,
        bs.s_recent,
        GREATEST(
            7,
            LEAST(p.threshold_days, CURRENT_DATE - fu.first_day + 1)
        )::INT AS obs_days,
        (
            bs.total_consumption > 0
            AND bs.oldest_age_days >= 7
            AND bs.movement_count >= 3
        ) AS is_reliable
    FROM bucket_sums bs
    CROSS JOIN params p
    JOIN first_use fu ON fu.product_part_id = bs.product_part_id
),
weighted_calc AS (
    SELECT
        wr.product_part_id,
        wr.movement_count,
        wr.total_consumption,
        wr.obs_days AS effective_days,
        CASE
            WHEN wr.total_consumption <= 0 THEN 0::NUMERIC
            ELSE wr.total_consumption::NUMERIC / wr.obs_days
        END AS daily_consumption_simple,
        wr.is_reliable,
        CASE
            WHEN wr.is_reliable AND wr.total_consumption > 0 THEN
                0.75 * (wr.total_consumption::NUMERIC / wr.obs_days)
              + 0.25 * (wr.s_recent / LEAST(7, wr.obs_days))
            ELSE 0::NUMERIC
        END AS daily_consumption_weighted
    FROM weighted_raw wr
),
part_product_category AS (
    SELECT
        bp.product_part_id,
        COALESCE(c.name, 'Senza categoria') AS category_name
    FROM buy_parts bp
    JOIN inventory."Product" pr ON pr.id = bp.product_id
    LEFT JOIN inventory."Item" pi ON pi.id = pr."itemId"
    LEFT JOIN inventory."Category" c ON c.id = pi."categoryId"
),
category_seasonal AS (
    -- Stessa stagionalità anno su anno di v_item_consumption_demand.
    SELECT
        COALESCE(c.name, 'Senza categoria') AS category_name,
        CASE
            WHEN MIN((m.date AT TIME ZONE 'UTC')::DATE) <= CURRENT_DATE - 365 - p.threshold_days
             AND SUM(CASE
                    WHEN (m.date AT TIME ZONE 'UTC')::DATE >= CURRENT_DATE - 365 - p.threshold_days
                     AND (m.date AT TIME ZONE 'UTC')::DATE < CURRENT_DATE - 365
                    THEN m.quantity ELSE 0 END) > 0
            THEN LEAST(
                2::NUMERIC,
                GREATEST(
                    0.5::NUMERIC,
                    SUM(CASE
                        WHEN (m.date AT TIME ZONE 'UTC')::DATE >= CURRENT_DATE - 365
                         AND (m.date AT TIME ZONE 'UTC')::DATE < CURRENT_DATE - 365 + p.threshold_days
                        THEN m.quantity ELSE 0 END)::NUMERIC
                    / SUM(CASE
                        WHEN (m.date AT TIME ZONE 'UTC')::DATE >= CURRENT_DATE - 365 - p.threshold_days
                         AND (m.date AT TIME ZONE 'UTC')::DATE < CURRENT_DATE - 365
                        THEN m.quantity ELSE 0 END)::NUMERIC
                )
            )
            ELSE 1::NUMERIC
        END AS seasonal_factor
    FROM inventory."Movement" m
    JOIN inventory."Item" i ON i.id = m."itemId"
    LEFT JOIN inventory."Category" c ON c.id = i."categoryId"
    CROSS JOIN params p
    WHERE m.type IN ('USO', 'VENDITA', 'TRASH')
      AND i.type <> 'TOOL'
    GROUP BY COALESCE(c.name, 'Senza categoria'), p.threshold_days
),
seasonal AS (
    SELECT ppc.product_part_id, COALESCE(cs.seasonal_factor, 1::NUMERIC) AS seasonal_factor
    FROM part_product_category ppc
    LEFT JOIN category_seasonal cs ON cs.category_name = ppc.category_name
)
SELECT
    bp.product_part_id,
    COALESCE(wc.daily_consumption_weighted, 0)::NUMERIC(14, 6) AS daily_consumption_weighted,
    COALESCE(wc.daily_consumption_simple, 0)::NUMERIC(14, 6) AS daily_consumption_simple,
    COALESCE(wc.is_reliable, FALSE) AS is_reliable,
    COALESCE(wc.movement_count, 0) AS movement_count,
    COALESCE(wc.effective_days, 0) AS effective_days,
    COALESCE(wc.total_consumption, 0)::BIGINT AS total_consumption,
    -- Domanda da ordini di produzione attivi (parti BUY consumate dalla BOM,
    -- quota ancora da produrre). Vedi v_product_part_reserved_stock.
    COALESCE(rps.reserved_quantity, 0)::INT AS demand_from_production,
    0::INT AS demand_from_assembly,
    COALESCE(se.seasonal_factor, 1::NUMERIC)::NUMERIC(8, 4) AS seasonal_factor,
    (
        COALESCE(wc.daily_consumption_weighted, 0::NUMERIC)
        * COALESCE(se.seasonal_factor, 1::NUMERIC)
    )::NUMERIC(14, 6) AS adjusted_daily_consumption
FROM buy_parts bp
LEFT JOIN weighted_calc wc ON wc.product_part_id = bp.product_part_id
LEFT JOIN inventory_views.v_product_part_reserved_stock rps ON rps.product_part_id = bp.product_part_id
LEFT JOIN seasonal se ON se.product_part_id = bp.product_part_id;

-- ============================================================================
-- VIEW: v_item_spec_consumption_demand — una riga per ItemSpec
-- Consumi e domanda BOM aggregati sulla famiglia (COALESCE Movement.itemSpecId,
-- Item.itemSpecId). La domanda produzione materiali è in grammi convertiti
-- in bobine del SKU preferito (solo bom_priority = 0).
-- Consumo MATERIAL: quantity movimenti (bobine SKU) convertita in unità del
-- SKU preferito, allineata a v_item_spec_stock_position.effective_units.
-- Domanda C/P/U da ProductOrder: solo ordini NON legati a un AssemblyOrder
-- (altrimenti lo stesso fabbisogno è già in demand_from_assembly).
-- ============================================================================
CREATE OR REPLACE VIEW inventory_views.v_item_spec_consumption_demand AS
WITH params AS (
    SELECT GREATEST(
        COALESCE(
            (
                SELECT
                    CASE
                        WHEN s.value IS NULL THEN 30
                        WHEN jsonb_typeof(s.value::jsonb) = 'number' THEN (s.value::text)::INT
                        WHEN (s.value::jsonb) ? 'days' THEN (s.value::jsonb->>'days')::INT
                        WHEN s.value::text ~ '^[0-9]+$' THEN s.value::text::INT
                        ELSE 30
                    END
                FROM inventory."Settings" s
                WHERE s.name = 'STOCK_THRESHOLD'
                LIMIT 1
            ),
            30
        ),
        1
    ) AS threshold_days
),
per_spec_movements AS (
    SELECT
        COALESCE(m."itemSpecId", i."itemSpecId") AS spec_id,
        CASE
            WHEN s.type = 'MATERIAL'
             AND COALESCE(pos.preferred_weight_g, 0) > 0
             AND (COALESCE(i.weight, sw.weight, 0)::NUMERIC * 1000) > 0
            THEN m.quantity::NUMERIC
                 * (COALESCE(i.weight, sw.weight, 0)::NUMERIC * 1000)
                 / pos.preferred_weight_g
            ELSE m.quantity::NUMERIC
        END AS quantity,
        m.date,
        (CURRENT_DATE - (m.date AT TIME ZONE 'UTC')::DATE)::INT AS days_ago
    FROM inventory."Movement" m
    LEFT JOIN inventory."Item" i ON i.id = m."itemId"
    LEFT JOIN inventory."StandardWeight" sw ON sw.id = i."standardWeightId"
    LEFT JOIN inventory."ItemSpec" s
      ON s.id = COALESCE(m."itemSpecId", i."itemSpecId")
    LEFT JOIN inventory_views.v_item_spec_stock_position pos
      ON pos.spec_id = s.id
    CROSS JOIN params p
    WHERE COALESCE(m."itemSpecId", i."itemSpecId") IS NOT NULL
      AND m.type IN ('USO', 'VENDITA', 'TRASH')
      AND m.date >= CURRENT_TIMESTAMP - (p.threshold_days::TEXT || ' days')::INTERVAL
),
first_use AS (
    SELECT
        COALESCE(m."itemSpecId", i."itemSpecId") AS spec_id,
        MIN((m.date AT TIME ZONE 'UTC')::DATE) AS first_day
    FROM inventory."Movement" m
    LEFT JOIN inventory."Item" i ON i.id = m."itemId"
    WHERE COALESCE(m."itemSpecId", i."itemSpecId") IS NOT NULL
      AND m.type IN ('USO', 'VENDITA', 'TRASH')
    GROUP BY COALESCE(m."itemSpecId", i."itemSpecId")
),
bucket_sums AS (
    SELECT
        pm.spec_id,
        SUM(CASE WHEN pm.days_ago >= 0 AND pm.days_ago < 7 THEN pm.quantity ELSE 0 END)::NUMERIC AS s_recent,
        COUNT(*)::INT AS movement_count,
        SUM(pm.quantity)::NUMERIC AS total_exact,
        CEIL(SUM(pm.quantity))::BIGINT AS total_consumption,
        (CURRENT_DATE - MIN((pm.date AT TIME ZONE 'UTC')::DATE) + 1)::INT AS oldest_age_days
    FROM per_spec_movements pm
    GROUP BY pm.spec_id
),
-- Stessa velocità su calendario di v_item_consumption_demand.
weighted_raw AS (
    SELECT
        bs.spec_id,
        bs.movement_count,
        bs.total_consumption,
        bs.total_exact,
        bs.oldest_age_days,
        bs.s_recent,
        GREATEST(
            7,
            LEAST(p.threshold_days, CURRENT_DATE - fu.first_day + 1)
        )::INT AS obs_days,
        (
            bs.total_consumption > 0
            AND bs.oldest_age_days >= 7
            AND bs.movement_count >= 3
        ) AS is_reliable
    FROM bucket_sums bs
    CROSS JOIN params p
    JOIN first_use fu ON fu.spec_id = bs.spec_id
),
weighted_calc AS (
    SELECT
        wr.spec_id,
        wr.movement_count,
        wr.total_consumption,
        wr.obs_days AS effective_days,
        CASE
            WHEN wr.total_exact <= 0 THEN 0::NUMERIC
            ELSE wr.total_exact / wr.obs_days
        END AS daily_consumption_simple,
        wr.is_reliable,
        CASE
            WHEN wr.is_reliable AND wr.total_exact > 0 THEN
                0.75 * (wr.total_exact / wr.obs_days)
              + 0.25 * (wr.s_recent / LEAST(7, wr.obs_days))
            ELSE 0::NUMERIC
        END AS daily_consumption_weighted
    FROM weighted_raw wr
),
pending_assembly AS (
    SELECT
        ao.id,
        ao."productId" AS product_id,
        ao."skuId" AS sku_id,
        GREATEST(ao."quantityToAssemble" - ao."quantityAssembled", 0)::NUMERIC AS remain
    FROM inventory."AssemblyOrder" ao
    WHERE ao.status NOT IN ('ASSEMBLY_COMPLETED', 'CANCELLED')
      AND GREATEST(ao."quantityToAssemble" - ao."quantityAssembled", 0) > 0
),
assembly_lines AS (
    SELECT c."itemSpecId" AS spec_id, SUM(c.quantity * pa.remain)::NUMERIC AS qty
    FROM pending_assembly pa
    JOIN inventory."ProductToComponent" c
      ON c."productId" = pa.product_id
     AND c.priority = 0
     AND (c."skuId" IS NULL OR c."skuId" = pa.sku_id)
    WHERE c."itemSpecId" IS NOT NULL
    GROUP BY c."itemSpecId"
    UNION ALL
    SELECT p."itemSpecId" AS spec_id, SUM(p.quantity * pa.remain)::NUMERIC AS qty
    FROM pending_assembly pa
    JOIN inventory."ProductToPackage" p
      ON p."productId" = pa.product_id
     AND p.priority = 0
     AND (p."skuId" IS NULL OR p."skuId" = pa.sku_id)
    WHERE p."itemSpecId" IS NOT NULL
    GROUP BY p."itemSpecId"
    UNION ALL
    SELECT u."itemSpecId" AS spec_id, SUM(u.quantity * pa.remain)::NUMERIC AS qty
    FROM pending_assembly pa
    JOIN inventory."ProductToUtility" u
      ON u."productId" = pa.product_id
     AND u.priority = 0
     AND (u."skuId" IS NULL OR u."skuId" = pa.sku_id)
    WHERE u."itemSpecId" IS NOT NULL
    GROUP BY u."itemSpecId"
),
assembly_demand_by_spec AS (
    SELECT spec_id, SUM(qty)::NUMERIC AS demand_qty
    FROM assembly_lines
    GROUP BY spec_id
),
-- Domanda produzione per spec: BOM diretta (non v_product_order_required_items),
-- così un DROP+CREATE di quella view non rompe questa né richiede CASCADE.
active_product_orders AS (
    SELECT
        o.id AS product_order_id,
        o."productId" AS product_id,
        o."skuId" AS sku_id,
        o."assemblyOrderId" AS assembly_order_id,
        o."quantityToProduce" AS quantity_to_produce,
        GREATEST(o."quantityToProduce" - o."quantityProduced", 0) AS quantity_remaining
    FROM inventory."ProductOrder" o
    WHERE o."productionStatus" IN ('READY_TO_PRODUCE', 'PRODUCING', 'NEED_SUPPLIES')
),
required_parts_remaining AS (
    SELECT
        popp."productOrderId" AS product_order_id,
        popp."productPartId" AS product_part_id,
        GREATEST(popp.quantity - popp."quantityProduced", 0)::NUMERIC AS part_qty_remaining
    FROM inventory."ProductOrderProductPart" popp
    JOIN active_product_orders apo ON apo.product_order_id = popp."productOrderId"
    UNION ALL
    SELECT
        apo.product_order_id,
        pp.id AS product_part_id,
        (pp."quantityNeeded" * apo.quantity_remaining)::NUMERIC AS part_qty_remaining
    FROM active_product_orders apo
    JOIN inventory."ProductPart" pp ON pp."productId" = apo.product_id
    WHERE apo.quantity_to_produce > 0
      AND NOT EXISTS (
        SELECT 1
        FROM inventory."ProductOrderProductPart" x
        WHERE x."productOrderId" = apo.product_order_id
      )
),
production_lines AS (
    SELECT
        c."itemSpecId" AS spec_id,
        'Component'::TEXT AS kind,
        (c.quantity * apo.quantity_remaining)::NUMERIC AS qty,
        0 AS bom_priority
    FROM active_product_orders apo
    JOIN inventory."ProductToComponent" c
      ON c."productId" = apo.product_id
     AND c.priority = 0
     AND (c."skuId" IS NULL OR c."skuId" = apo.sku_id)
    WHERE apo.quantity_to_produce > 0
      AND apo.assembly_order_id IS NULL
      AND c."itemSpecId" IS NOT NULL
    UNION ALL
    SELECT
        p."itemSpecId" AS spec_id,
        'Packaging'::TEXT AS kind,
        (p.quantity * apo.quantity_remaining)::NUMERIC AS qty,
        0 AS bom_priority
    FROM active_product_orders apo
    JOIN inventory."ProductToPackage" p
      ON p."productId" = apo.product_id
     AND p.priority = 0
     AND (p."skuId" IS NULL OR p."skuId" = apo.sku_id)
    WHERE apo.quantity_to_produce > 0
      AND apo.assembly_order_id IS NULL
      AND p."itemSpecId" IS NOT NULL
    UNION ALL
    SELECT
        u."itemSpecId" AS spec_id,
        'Utility'::TEXT AS kind,
        (u.quantity * apo.quantity_remaining)::NUMERIC AS qty,
        0 AS bom_priority
    FROM active_product_orders apo
    JOIN inventory."ProductToUtility" u
      ON u."productId" = apo.product_id
     AND u.priority = 0
     AND (u."skuId" IS NULL OR u."skuId" = apo.sku_id)
    WHERE apo.quantity_to_produce > 0
      AND apo.assembly_order_id IS NULL
      AND u."itemSpecId" IS NOT NULL
    UNION ALL
    SELECT
        mb."materialSpecId" AS spec_id,
        'Material'::TEXT AS kind,
        (mb."usedWeight" * rp.part_qty_remaining)::NUMERIC AS qty,
        mb.priority AS bom_priority
    FROM required_parts_remaining rp
    JOIN active_product_orders apo ON apo.product_order_id = rp.product_order_id
    JOIN inventory."ProductPart" pp ON pp.id = rp.product_part_id
    JOIN inventory."ProductPartMaterial" mb
      ON mb."productPartId" = rp.product_part_id
    WHERE pp."sourceType" = 'MAKE'
      AND mb."materialSpecId" IS NOT NULL
),
production_demand AS (
    SELECT spec_id, kind, SUM(qty) AS total_needed
    FROM production_lines
    WHERE kind <> 'Material' OR bom_priority = 0
    GROUP BY spec_id, kind
),
production_demand_by_spec AS (
    SELECT
        pd.spec_id,
        SUM(
            CASE
                WHEN pd.kind = 'Material' THEN
                    CASE
                        WHEN COALESCE(pos.preferred_weight_g, 0) > 0 THEN
                            CEIL(pd.total_needed / pos.preferred_weight_g)
                        ELSE 0
                    END
                ELSE pd.total_needed
            END
        )::INT AS demand_qty
    FROM production_demand pd
    LEFT JOIN inventory_views.v_item_spec_stock_position pos ON pos.spec_id = pd.spec_id
    GROUP BY pd.spec_id
),
category_seasonal AS (
    -- Stessa stagionalità anno su anno di v_item_consumption_demand.
    SELECT
        COALESCE(c.name, 'Senza categoria') AS category_name,
        CASE
            WHEN MIN((m.date AT TIME ZONE 'UTC')::DATE) <= CURRENT_DATE - 365 - p.threshold_days
             AND SUM(CASE
                    WHEN (m.date AT TIME ZONE 'UTC')::DATE >= CURRENT_DATE - 365 - p.threshold_days
                     AND (m.date AT TIME ZONE 'UTC')::DATE < CURRENT_DATE - 365
                    THEN m.quantity ELSE 0 END) > 0
            THEN LEAST(
                2::NUMERIC,
                GREATEST(
                    0.5::NUMERIC,
                    SUM(CASE
                        WHEN (m.date AT TIME ZONE 'UTC')::DATE >= CURRENT_DATE - 365
                         AND (m.date AT TIME ZONE 'UTC')::DATE < CURRENT_DATE - 365 + p.threshold_days
                        THEN m.quantity ELSE 0 END)::NUMERIC
                    / SUM(CASE
                        WHEN (m.date AT TIME ZONE 'UTC')::DATE >= CURRENT_DATE - 365 - p.threshold_days
                         AND (m.date AT TIME ZONE 'UTC')::DATE < CURRENT_DATE - 365
                        THEN m.quantity ELSE 0 END)::NUMERIC
                )
            )
            ELSE 1::NUMERIC
        END AS seasonal_factor
    FROM inventory."Movement" m
    JOIN inventory."Item" i ON i.id = m."itemId"
    LEFT JOIN inventory."Category" c ON c.id = i."categoryId"
    CROSS JOIN params p
    WHERE m.type IN ('USO', 'VENDITA', 'TRASH')
      AND i.type <> 'TOOL'
    GROUP BY COALESCE(c.name, 'Senza categoria'), p.threshold_days
),
spec_category AS (
    SELECT
        spec.id AS spec_id,
        COALESCE(c.name, 'Senza categoria') AS category_name
    FROM inventory."ItemSpec" spec
    LEFT JOIN inventory_views.v_item_spec_resolved r ON r.spec_id = spec.id
    LEFT JOIN inventory."Item" i ON i.id = r.item_id
    LEFT JOIN inventory."Category" c ON c.id = i."categoryId"
),
seasonal AS (
    SELECT sc.spec_id, COALESCE(cs.seasonal_factor, 1::NUMERIC) AS seasonal_factor
    FROM spec_category sc
    LEFT JOIN category_seasonal cs ON cs.category_name = sc.category_name
)
SELECT
    spec.id AS spec_id,
    COALESCE(wc.daily_consumption_weighted, 0)::NUMERIC(14, 6) AS daily_consumption_weighted,
    COALESCE(wc.daily_consumption_simple, 0)::NUMERIC(14, 6) AS daily_consumption_simple,
    COALESCE(wc.is_reliable, FALSE) AS is_reliable,
    COALESCE(wc.movement_count, 0) AS movement_count,
    COALESCE(wc.effective_days, 0) AS effective_days,
    COALESCE(wc.total_consumption, 0)::BIGINT AS total_consumption,
    COALESCE(pd.demand_qty, 0)::INT AS demand_from_production,
    COALESCE(CEIL(ad.demand_qty), 0)::INT AS demand_from_assembly,
    COALESCE(se.seasonal_factor, 1::NUMERIC)::NUMERIC(8, 4) AS seasonal_factor,
    (
        COALESCE(wc.daily_consumption_weighted, 0::NUMERIC)
        * COALESCE(se.seasonal_factor, 1::NUMERIC)
    )::NUMERIC(14, 6) AS adjusted_daily_consumption
FROM inventory."ItemSpec" spec
LEFT JOIN weighted_calc wc ON wc.spec_id = spec.id
LEFT JOIN production_demand_by_spec pd ON pd.spec_id = spec.id
LEFT JOIN assembly_demand_by_spec ad ON ad.spec_id = spec.id
LEFT JOIN seasonal se ON se.spec_id = spec.id;
