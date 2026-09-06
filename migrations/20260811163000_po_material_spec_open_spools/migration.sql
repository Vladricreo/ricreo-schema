-- Material Spec fallback + open spool grams for production order BOM
DROP VIEW IF EXISTS inventory_views.v_item_consumption_demand;
DROP VIEW IF EXISTS inventory_views.v_product_order_cost_summary;
DROP VIEW IF EXISTS inventory_views.v_item_reserved_stock;
DROP VIEW IF EXISTS inventory_views.v_product_order_required_items;

CREATE VIEW inventory_views.v_product_order_required_items AS
WITH order_base AS (
  SELECT
    o.id AS product_order_id,
    o.number AS product_order_number,
    o."productId" AS product_id,
    o."skuId" AS sku_id,
    o."assemblyOrderId" AS assembly_order_id,
    ao.number AS assembly_order_number,
    o."quantityToProduce" AS quantity_to_produce,
    -- Quantità ancora da produrre (per il calcolo della domanda di riordino):
    -- gli ordini in corso non devono contare la parte già prodotta.
    GREATEST(o."quantityToProduce" - o."quantityProduced", 0) AS quantity_remaining,
    (o."quantityToProduce" = 0) AS is_parts_only
  FROM inventory."ProductOrder" o
  LEFT JOIN inventory."AssemblyOrder" ao ON ao.id = o."assemblyOrderId"
),
-- Quantità parti richieste:
-- - se esistono righe ProductOrderProductPart, usiamo quelle (ordini custom inclusi)
-- - altrimenti fallback (legacy): ProductPart.quantityNeeded * quantityToProduce
-- `part_qty` = totale richiesto dall'ordine (per BOM/costi).
-- `part_qty_remaining` = ancora da produrre (per la domanda di riordino).
required_parts AS (
  SELECT
    popp."productOrderId" AS product_order_id,
    popp."productPartId" AS product_part_id,
    (popp.quantity)::NUMERIC AS part_qty,
    GREATEST(popp.quantity - popp."quantityProduced", 0)::NUMERIC AS part_qty_remaining
  FROM inventory."ProductOrderProductPart" popp
  UNION ALL
  SELECT
    ob.product_order_id,
    pp.id AS product_part_id,
    (pp."quantityNeeded" * ob.quantity_to_produce)::NUMERIC AS part_qty,
    (pp."quantityNeeded" * ob.quantity_remaining)::NUMERIC AS part_qty_remaining
  FROM order_base ob
  JOIN inventory."ProductPart" pp ON pp."productId" = ob.product_id
  WHERE ob.quantity_to_produce > 0
    AND NOT EXISTS (
      SELECT 1
      FROM inventory."ProductOrderProductPart" x
      WHERE x."productOrderId" = ob.product_order_id
    )
),
-- Componenti (solo per ordini "normali")
component_lines AS (
  SELECT
    ob.product_order_id,
    ob.product_order_number,
    ob.product_id,
    ob.sku_id,
    ob.assembly_order_id,
    ob.assembly_order_number,
    'Component'::TEXT AS kind,
    ri.item_id,
    c."itemSpecId" AS item_spec_id,
    (c.quantity * ob.quantity_to_produce)::NUMERIC AS quantity_needed,
    NULL::NUMERIC AS quantity_needed_grams,
    (c.quantity * ob.quantity_remaining)::NUMERIC AS quantity_needed_remaining,
    NULL::NUMERIC AS quantity_needed_grams_remaining,
    NULL::NUMERIC AS used_weight_grams,
    NULL::UUID AS product_part_id,
    0 AS bom_priority
  FROM order_base ob
  JOIN inventory."ProductToComponent" c
    ON c."productId" = ob.product_id
   AND c.priority = 0
   AND (c."skuId" IS NULL OR c."skuId" = ob.sku_id)
  JOIN inventory_views.v_item_spec_resolved ri
    ON ri.spec_id = c."itemSpecId"
  WHERE ob.quantity_to_produce > 0
),
-- Packaging (solo priorità 0, solo per ordini "normali")
package_lines AS (
  SELECT
    ob.product_order_id,
    ob.product_order_number,
    ob.product_id,
    ob.sku_id,
    ob.assembly_order_id,
    ob.assembly_order_number,
    'Packaging'::TEXT AS kind,
    ri.item_id,
    p."itemSpecId" AS item_spec_id,
    (p.quantity * ob.quantity_to_produce)::NUMERIC AS quantity_needed,
    NULL::NUMERIC AS quantity_needed_grams,
    (p.quantity * ob.quantity_remaining)::NUMERIC AS quantity_needed_remaining,
    NULL::NUMERIC AS quantity_needed_grams_remaining,
    NULL::NUMERIC AS used_weight_grams,
    NULL::UUID AS product_part_id,
    0 AS bom_priority
  FROM order_base ob
  JOIN inventory."ProductToPackage" p
    ON p."productId" = ob.product_id
   AND p.priority = 0
   AND (p."skuId" IS NULL OR p."skuId" = ob.sku_id)
  JOIN inventory_views.v_item_spec_resolved ri
    ON ri.spec_id = p."itemSpecId"
  WHERE ob.quantity_to_produce > 0
),
-- Utility (consumabili per stage) - solo priorità 0, solo per ordini "normali"
utility_lines AS (
  SELECT
    ob.product_order_id,
    ob.product_order_number,
    ob.product_id,
    ob.sku_id,
    ob.assembly_order_id,
    ob.assembly_order_number,
    'Utility'::TEXT AS kind,
    ri.item_id,
    u."itemSpecId" AS item_spec_id,
    (u.quantity * ob.quantity_to_produce)::NUMERIC AS quantity_needed,
    NULL::NUMERIC AS quantity_needed_grams,
    (u.quantity * ob.quantity_remaining)::NUMERIC AS quantity_needed_remaining,
    NULL::NUMERIC AS quantity_needed_grams_remaining,
    NULL::NUMERIC AS used_weight_grams,
    NULL::UUID AS product_part_id,
    0 AS bom_priority
  FROM order_base ob
  JOIN inventory."ProductToUtility" u
    ON u."productId" = ob.product_id
   AND u.priority = 0
   AND (u."skuId" IS NULL OR u."skuId" = ob.sku_id)
  JOIN inventory_views.v_item_spec_resolved ri
    ON ri.spec_id = u."itemSpecId"
  WHERE ob.quantity_to_produce > 0
),
-- Materiali per le parti (MAKE) - grammi necessari, tutte le Spec di ripiego
material_lines AS (
  SELECT
    ob.product_order_id,
    ob.product_order_number,
    ob.product_id,
    ob.sku_id,
    ob.assembly_order_id,
    ob.assembly_order_number,
    'Material'::TEXT AS kind,
    ri.item_id,
    mb."materialSpecId" AS item_spec_id,
    NULL::NUMERIC AS quantity_needed,
    (mb."usedWeight" * rp.part_qty)::NUMERIC AS quantity_needed_grams,
    NULL::NUMERIC AS quantity_needed_remaining,
    (mb."usedWeight" * rp.part_qty_remaining)::NUMERIC AS quantity_needed_grams_remaining,
    (mb."usedWeight")::NUMERIC AS used_weight_grams,
    rp.product_part_id,
    mb.priority AS bom_priority
  FROM required_parts rp
  JOIN order_base ob ON ob.product_order_id = rp.product_order_id
  JOIN inventory."ProductPart" pp ON pp.id = rp.product_part_id
  JOIN inventory."ProductPartMaterial" mb
    ON mb."productPartId" = rp.product_part_id
  JOIN inventory_views.v_item_spec_resolved ri
    ON ri.spec_id = mb."materialSpecId"
  WHERE pp."sourceType" = 'MAKE'
)
SELECT
  l.product_order_id,
  l.product_order_number,
  l.product_id,
  l.sku_id,
  l.assembly_order_id,
  l.assembly_order_number,
  l.kind,
  l.item_id,
  l.item_spec_id,
  l.product_part_id,
  -- Quantità: per Material è in grammi, per gli altri è in pezzi
  COALESCE(l.quantity_needed, l.quantity_needed_grams, 0)::NUMERIC AS quantity_needed,
  -- Disponibilità Material: bobine sigillate (inStock × g) + spool ACTIVE aperte.
  -- Nota: la quantità riservata è deprecata e NON viene sottratta dalla disponibilità.
  CASE
    WHEN l.kind = 'Material' THEN
      (
        GREATEST(COALESCE(i."inStock", 0), 0)::NUMERIC
          * (COALESCE(i.weight, sw.weight, 0)::NUMERIC * 1000)
      )
      + COALESCE(open_spool.remaining_grams, 0)
    ELSE
      GREATEST(
        COALESCE(i."inStock", 0),
        0
      )::NUMERIC
  END AS quantity_available,
  i.name AS item_name,
  i.sku AS item_sku,
  i."imageUrl" AS item_image_url,
  -- Costo unitario: Material = €/g, altri = €/pz
  CASE
    WHEN l.kind = 'Material' THEN
      CASE
        WHEN (COALESCE(i.weight, sw.weight, 0)::NUMERIC * 1000) > 0
          THEN (i.price::NUMERIC / (COALESCE(i.weight, sw.weight, 0)::NUMERIC * 1000))
        ELSE 0
      END
    ELSE
      COALESCE(i.price, 0)::NUMERIC
  END AS unit_cost,
  -- Costo totale riga
  (
    COALESCE(
      CASE
        WHEN l.kind = 'Material' THEN
          CASE
            WHEN (COALESCE(i.weight, sw.weight, 0)::NUMERIC * 1000) > 0
              THEN (i.price::NUMERIC / (COALESCE(i.weight, sw.weight, 0)::NUMERIC * 1000))
            ELSE 0
          END
        ELSE
          COALESCE(i.price, 0)::NUMERIC
      END,
      0
    ) * COALESCE(l.quantity_needed, l.quantity_needed_grams, 0)::NUMERIC
  ) AS total_cost,
  -- Lotto suggerito: primo lotto OPEN (FIFO) se esiste
  lot.code AS suggested_lot_code,
  -- Quantità ancora da produrre (stessa unità di quantity_needed): usata per la
  -- domanda di riordino, così gli ordini in corso non sovrastimano il fabbisogno.
  COALESCE(l.quantity_needed_remaining, l.quantity_needed_grams_remaining, 0)::NUMERIC AS quantity_needed_remaining,
  -- Tier Spec materiali (0 = prima scelta). Per Comp/Pkg/Util è sempre 0.
  COALESCE(l.bom_priority, 0)::INT AS bom_priority
FROM (
  SELECT * FROM component_lines
  UNION ALL SELECT * FROM package_lines
  UNION ALL SELECT * FROM utility_lines
  UNION ALL SELECT * FROM material_lines
) l
JOIN inventory."Item" i ON i.id = l.item_id
LEFT JOIN inventory."StandardWeight" sw ON sw.id = i."standardWeightId"
LEFT JOIN LATERAL (
  SELECT SUM(GREATEST(fs."remainingWeight", 0))::NUMERIC AS remaining_grams
  FROM "print-farm"."FilamentSpool" fs
  WHERE fs."itemId" = i.id
    AND fs.status = 'ACTIVE'
    AND fs."remainingWeight" > 0
) open_spool ON true
LEFT JOIN LATERAL (
  SELECT il.code
  FROM inventory."InventoryLot" il
  WHERE il."itemId" = i.id
    AND il.status = 'OPEN'
  ORDER BY il."createdAt" ASC
  LIMIT 1
) lot ON true;

-- 1.11.3: Aggregato per ProductOrder (costo totale + costo unitario)
-- Costi materiali: solo Spec primaria (bom_priority = 0). Le Spec di ripiego
-- restano nella BOM per la copertura stock, ma non raddoppiano il costo.
CREATE OR REPLACE VIEW inventory_views.v_product_order_cost_summary AS
WITH totals AS (
  SELECT
    ri.product_order_id,
    SUM(ri.total_cost)::NUMERIC AS items_total_cost
  FROM inventory_views.v_product_order_required_items ri
  WHERE ri.kind <> 'Material' OR ri.bom_priority = 0
  GROUP BY ri.product_order_id
),
base AS (
  SELECT
    o.id AS product_order_id,
    o.number AS product_order_number,
    o."productId" AS product_id,
    o."skuId" AS sku_id,
    o."assemblyOrderId" AS assembly_order_id,
    ao.number AS assembly_order_number,
    o."quantityToProduce" AS quantity_to_produce,
    (o."quantityToProduce" = 0) AS is_parts_only,
    o."productionStatus" AS production_status,
    o.priority,
    o."createdAt" AS created_at,
    o."updatedAt" AS updated_at,
    COALESCE(p."laborCost", 0)::NUMERIC AS labor_cost_unit
  FROM inventory."ProductOrder" o
  JOIN inventory."Product" p ON p.id = o."productId"
  LEFT JOIN inventory."AssemblyOrder" ao ON ao.id = o."assemblyOrderId"
)
SELECT
  b.product_order_id,
  b.product_order_number,
  b.product_id,
  b.sku_id,
  b.assembly_order_id,
  b.assembly_order_number,
  b.quantity_to_produce,
  b.is_parts_only,
  b.production_status,
  b.priority,
  b.created_at,
  b.updated_at,
  -- Totale item (materiali/componenti/packaging/utility)
  COALESCE(t.items_total_cost, 0)::NUMERIC AS items_total_cost,
  -- Manodopera solo per ordini "normali" (qty > 0)
  CASE
    WHEN b.quantity_to_produce > 0 THEN (b.labor_cost_unit * b.quantity_to_produce)::NUMERIC
    ELSE 0
  END AS labor_total_cost,
  -- Totale complessivo richiesto
  (
    COALESCE(t.items_total_cost, 0)
    + CASE
        WHEN b.quantity_to_produce > 0 THEN (b.labor_cost_unit * b.quantity_to_produce)
        ELSE 0
      END
  )::NUMERIC AS total_cost,
  -- Costo unitario (solo per ordini "normali")
  CASE
    WHEN b.quantity_to_produce > 0 THEN
      (
        COALESCE(t.items_total_cost, 0)
        + (b.labor_cost_unit * b.quantity_to_produce)
      ) / b.quantity_to_produce
    ELSE NULL
  END AS unit_cost
FROM base b
LEFT JOIN totals t ON t.product_order_id = b.product_order_id;

-- ============================================================================
-- SEZIONE 1.12: Item Reserved Stock (BOM ordini di produzione attivi)
-- ============================================================================
CREATE OR REPLACE VIEW inventory_views.v_item_reserved_stock AS
WITH active_orders AS (
  SELECT id AS product_order_id
  FROM inventory."ProductOrder"
  WHERE "productionStatus" IN ('READY_TO_PRODUCE', 'PRODUCING', 'NEED_SUPPLIES')
),
required_agg AS (
  -- Usiamo `quantity_needed_remaining` (ancora da produrre) invece del totale:
  -- la quota già prodotta ha gia consumato il materiale, quindi non va
  -- riconteggiata come domanda di riordino.
  -- Materiali: solo Spec primaria (bom_priority = 0), come i costi.
  SELECT 
    r.item_id,
    r.kind,
    SUM(r.quantity_needed_remaining) AS total_needed
  FROM inventory_views.v_product_order_required_items r
  JOIN active_orders ao ON ao.product_order_id = r.product_order_id
  WHERE r.kind <> 'Material' OR r.bom_priority = 0
  GROUP BY r.item_id, r.kind
),
item_reserved AS (
  SELECT 
    ra.item_id,
    CASE 
      WHEN ra.kind = 'Material' THEN
        -- CEIL: anche una frazione di bobina (es. 500g su 1kg) richiede 1 unità da acquistare.
        -- FLOOR azzerava la domanda di produzione per fabbisogni sotto 1 bobina intera.
        CASE 
          WHEN (COALESCE(i.weight, sw.weight, 0)::NUMERIC * 1000) > 0 THEN
            CEIL(ra.total_needed / (COALESCE(i.weight, sw.weight, 0)::NUMERIC * 1000))
          ELSE 0
        END
      ELSE
        ra.total_needed
    END::INT AS reserved_qty
  FROM required_agg ra
  JOIN inventory."Item" i ON i.id = ra.item_id
  LEFT JOIN inventory."StandardWeight" sw ON sw.id = i."standardWeightId"
)
SELECT 
  item_id,
  SUM(reserved_qty)::INT AS reserved_quantity
FROM item_reserved
GROUP BY item_id;

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
bucket_sums AS (
    SELECT
        item_id,
        SUM(CASE WHEN days_ago >= 0 AND days_ago < 8 THEN quantity ELSE 0 END)::BIGINT AS s0,
        SUM(CASE WHEN days_ago >= 8 AND days_ago < 31 THEN quantity ELSE 0 END)::BIGINT AS s1,
        -- Nota: con threshold default 30gg il bucket s2 è tipicamente vuoto (days_ago < 30).
        -- Resta utile se STOCK_THRESHOLD.days > 31.
        SUM(CASE WHEN days_ago >= 31 THEN quantity ELSE 0 END)::BIGINT AS s2,
        COUNT(*)::INT AS movement_count,
        SUM(quantity)::BIGINT AS total_consumption,
        (CURRENT_DATE - MIN((date AT TIME ZONE 'UTC')::DATE) + 1)::INT AS oldest_age_days
    FROM per_item_movements
    GROUP BY item_id
),
weighted_raw AS (
    SELECT
        bs.item_id,
        bs.movement_count,
        bs.total_consumption,
        bs.oldest_age_days,
        (
            (CASE WHEN bs.s0 > 0 THEN (bs.s0::NUMERIC / GREATEST(1, LEAST(8, bs.oldest_age_days)::NUMERIC)) * 3 ELSE 0::NUMERIC END)
          + (CASE WHEN bs.s1 > 0 THEN (bs.s1::NUMERIC / GREATEST(1, (LEAST(31, bs.oldest_age_days) - 8))::NUMERIC) * 2 ELSE 0::NUMERIC END)
          + (CASE WHEN bs.s2 > 0 THEN (bs.s2::NUMERIC / GREATEST(1, (bs.oldest_age_days - 31))::NUMERIC) * 1 ELSE 0::NUMERIC END)
        ) AS weighted_numerator,
        (
            (CASE WHEN bs.s0 > 0 THEN 3 ELSE 0 END)
          + (CASE WHEN bs.s1 > 0 THEN 2 ELSE 0 END)
          + (CASE WHEN bs.s2 > 0 THEN 1 ELSE 0 END)
        )::NUMERIC AS weighted_denominator,
        CASE
            WHEN bs.movement_count = 0 OR bs.total_consumption <= 0 THEN 0::NUMERIC
            ELSE bs.total_consumption::NUMERIC / GREATEST(1, bs.oldest_age_days::NUMERIC)
        END AS daily_simple,
        (
            bs.total_consumption > 0
            AND bs.oldest_age_days >= 7
            AND bs.movement_count >= 3
        ) AS is_reliable
    FROM bucket_sums bs
),
weighted_calc AS (
    SELECT
        wr.item_id,
        wr.movement_count,
        wr.total_consumption,
        wr.oldest_age_days AS effective_days,
        wr.daily_simple AS daily_consumption_simple,
        wr.is_reliable,
        CASE
            WHEN wr.is_reliable AND wr.weighted_denominator > 0 THEN wr.weighted_numerator / wr.weighted_denominator
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
category_annual AS (
    SELECT
        s.category_name,
        SUM(s.total_consumption)::NUMERIC / NULLIF(SUM(s.days_with_data), 0) AS avg_daily_year
    FROM inventory_views.v_dashboard_seasonality s
    GROUP BY s.category_name
),
item_category AS (
    SELECT
        i.id AS item_id,
        COALESCE(c.name, 'Senza categoria') AS category_name
    FROM inventory."Item" i
    LEFT JOIN inventory."Category" c ON c.id = i."categoryId"
),
seasonal AS (
    SELECT
        ic.item_id,
        LEAST(
            2::NUMERIC,
            GREATEST(
                0.5::NUMERIC,
                COALESCE(
                    cm.avg_daily_consumption::NUMERIC / NULLIF(ya.avg_daily_year, 0),
                    1::NUMERIC
                )
            )
        ) AS seasonal_factor
    FROM item_category ic
    LEFT JOIN category_annual ya ON ya.category_name = ic.category_name
    LEFT JOIN inventory_views.v_dashboard_seasonality cm
      ON cm.category_name = ic.category_name
     AND cm.month_of_year = EXTRACT(MONTH FROM CURRENT_DATE)::INT
)
SELECT
    i.id AS item_id,
    COALESCE(wc.daily_consumption_weighted, 0)::NUMERIC(14, 6) AS daily_consumption_weighted,
    COALESCE(wc.daily_consumption_simple, 0)::NUMERIC(14, 6) AS daily_consumption_simple,
    COALESCE(wc.is_reliable, FALSE) AS is_reliable,
    COALESCE(wc.movement_count, 0) AS movement_count,
    COALESCE(wc.effective_days, 0) AS effective_days,
    COALESCE(wc.total_consumption, 0)::BIGINT AS total_consumption,
    COALESCE(rs.reserved_quantity, 0) AS demand_from_production,
    COALESCE(CEIL(ad.demand_qty), 0)::INT AS demand_from_assembly,
    COALESCE(se.seasonal_factor, 1::NUMERIC)::NUMERIC(8, 4) AS seasonal_factor,
    (
        COALESCE(wc.daily_consumption_weighted, 0::NUMERIC)
        * COALESCE(se.seasonal_factor, 1::NUMERIC)
    )::NUMERIC(14, 6) AS adjusted_daily_consumption
FROM inventory."Item" i
LEFT JOIN weighted_calc wc ON wc.item_id = i.id
LEFT JOIN inventory_views.v_item_reserved_stock rs ON rs.item_id = i.id
LEFT JOIN assembly_demand_by_item ad ON ad.item_id = i.id
LEFT JOIN seasonal se ON se.item_id = i.id;

-- ============================================================================
-- VIEW: v_product_part_consumption_demand — una riga per ProductPart BUY
-- ============================================================================
