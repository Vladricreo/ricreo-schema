-- ============================================================================
-- Costi BOM divisi per SKU.
--
-- Componenti, imballaggio e utility possono essere legati a uno SKU specifico
-- (`skuId` valorizzato) oppure valere per tutti gli SKU del prodotto
-- (`skuId IS NULL`). `v_product_cost_breakdown` sommava tutte le righe
-- priority=0 senza guardare `skuId`: una scatola usata solo dallo SKU FBM
-- finiva anche nel costo dello SKU FBA, producendo un costo che nessuno SKU
-- sostiene realmente.
--
-- Cosa cambia:
--   * nuova view base `v_product_bom_variant_cost`: BOM C/P/U espansa per SKU
--     con la regola già usata dagli ordini (`skuId IS NULL OR skuId = <sku>`);
--   * `v_product_cost_breakdown` passa al criterio WORST CASE (lo SKU con la
--     variante più costosa) e guadagna 3 colonne in coda;
--   * nuove `v_sku_cost_breakdown` e `v_sku_pricing_summary` per il costo esatto
--     del singolo SKU.
--
-- CREATE OR REPLACE su `v_product_cost_breakdown`: le colonne esistenti restano
-- identiche in nome/ordine/tipo e le nuove sono aggiunte in coda, quindi
-- `v_product_pricing_summary` (e a cascata `mv_overview_sku_meta`) resta valida.
-- I valori di costo però cambiano: dopo il deploy va fatto il REFRESH delle
-- matview che leggono i costi prodotto (`mv_overview_sku_meta`,
-- `mv_sales_analytics_daily`).
--
-- Definizione canonica completa: prisma/custom_migrations/sql/product_cost_views.sql
--
-- Applicabile anche via psql / Supabase CLI. Se lo fai fuori da Prisma:
--   bunx prisma migrate resolve --applied 20260903160000_sku_cost_breakdown
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. BOM variante per SKU (view base)
-- Emette anche una riga con `sku_id IS NULL` per prodotto: aggregato delle sole
-- righe condivise, usato come fallback per i prodotti senza SKU.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE VIEW inventory_views.v_product_bom_variant_cost AS
WITH sku_scope AS (
    SELECT s."productId" AS product_id, s.id AS sku_id
    FROM inventory."Sku" s
    UNION ALL
    -- Riga "solo condiviso": `skuId = NULL` non matcha nessuna riga dedicata,
    -- quindi raccoglie esattamente la BOM comune a tutti gli SKU.
    SELECT pr.id AS product_id, NULL::UUID AS sku_id
    FROM inventory."Product" pr
),
component_cost AS (
    SELECT
        sc.product_id,
        sc.sku_id,
        SUM(COALESCE(i.price, 0)::NUMERIC * c.quantity::NUMERIC) AS cost,
        SUM(
            CASE
                WHEN c."skuId" IS NOT NULL
                  THEN COALESCE(i.price, 0)::NUMERIC * c.quantity::NUMERIC
                ELSE 0
            END
        ) AS dedicated_cost,
        SUM(CASE WHEN c."skuId" IS NOT NULL THEN 1 ELSE 0 END) AS dedicated_rows
    FROM sku_scope sc
    JOIN inventory."ProductToComponent" c
      ON c."productId" = sc.product_id
     AND c.priority = 0
     AND (c."skuId" IS NULL OR c."skuId" = sc.sku_id)
    JOIN inventory_views.v_item_spec_resolved ri ON ri.spec_id = c."itemSpecId"
    JOIN inventory."Item" i ON i.id = ri.item_id
    GROUP BY sc.product_id, sc.sku_id
),
package_cost AS (
    SELECT
        sc.product_id,
        sc.sku_id,
        SUM(COALESCE(i.price, 0)::NUMERIC * p.quantity::NUMERIC) AS cost,
        SUM(
            CASE
                WHEN p."skuId" IS NOT NULL
                  THEN COALESCE(i.price, 0)::NUMERIC * p.quantity::NUMERIC
                ELSE 0
            END
        ) AS dedicated_cost,
        SUM(CASE WHEN p."skuId" IS NOT NULL THEN 1 ELSE 0 END) AS dedicated_rows
    FROM sku_scope sc
    JOIN inventory."ProductToPackage" p
      ON p."productId" = sc.product_id
     AND p.priority = 0
     AND (p."skuId" IS NULL OR p."skuId" = sc.sku_id)
    JOIN inventory_views.v_item_spec_resolved ri ON ri.spec_id = p."itemSpecId"
    JOIN inventory."Item" i ON i.id = ri.item_id
    GROUP BY sc.product_id, sc.sku_id
),
utility_cost AS (
    SELECT
        sc.product_id,
        sc.sku_id,
        SUM(COALESCE(i.price, 0)::NUMERIC * u.quantity::NUMERIC) AS cost,
        SUM(
            CASE
                WHEN u."skuId" IS NOT NULL
                  THEN COALESCE(i.price, 0)::NUMERIC * u.quantity::NUMERIC
                ELSE 0
            END
        ) AS dedicated_cost,
        SUM(CASE WHEN u."skuId" IS NOT NULL THEN 1 ELSE 0 END) AS dedicated_rows
    FROM sku_scope sc
    JOIN inventory."ProductToUtility" u
      ON u."productId" = sc.product_id
     AND u.priority = 0
     AND (u."skuId" IS NULL OR u."skuId" = sc.sku_id)
    JOIN inventory_views.v_item_spec_resolved ri ON ri.spec_id = u."itemSpecId"
    JOIN inventory."Item" i ON i.id = ri.item_id
    GROUP BY sc.product_id, sc.sku_id
)
SELECT
    sc.product_id,
    sc.sku_id,
    COALESCE(cc.cost, 0)::DECIMAL(12,4) AS components_cost,
    COALESCE(pc.cost, 0)::DECIMAL(12,4) AS packaging_cost,
    COALESCE(uc.cost, 0)::DECIMAL(12,4) AS utilities_cost,
    (
        COALESCE(cc.cost, 0)
      + COALESCE(pc.cost, 0)
      + COALESCE(uc.cost, 0)
    )::DECIMAL(12,4) AS variant_cost,
    -- Quota di costo che esiste SOLO per questo SKU (righe con skuId valorizzato)
    (
        COALESCE(cc.dedicated_cost, 0)
      + COALESCE(pc.dedicated_cost, 0)
      + COALESCE(uc.dedicated_cost, 0)
    )::DECIMAL(12,4) AS dedicated_cost,
    -- Conta le righe, non il costo: una riga dedicata con prezzo 0 resta dedicata.
    (
        COALESCE(cc.dedicated_rows, 0)
      + COALESCE(pc.dedicated_rows, 0)
      + COALESCE(uc.dedicated_rows, 0)
    ) > 0 AS has_dedicated_bom
FROM sku_scope sc
LEFT JOIN component_cost cc
  ON cc.product_id = sc.product_id AND cc.sku_id IS NOT DISTINCT FROM sc.sku_id
LEFT JOIN package_cost pc
  ON pc.product_id = sc.product_id AND pc.sku_id IS NOT DISTINCT FROM sc.sku_id
LEFT JOIN utility_cost uc
  ON uc.product_id = sc.product_id AND uc.sku_id IS NOT DISTINCT FROM sc.sku_id;

-- ----------------------------------------------------------------------------
-- 2. Costo prodotto: C/P/U dallo SKU peggiore invece della somma di tutti
-- ----------------------------------------------------------------------------

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
    -- Solo le parti del piano ATTIVO: dopo una revisione le parti del piano esaurito
    -- restano in tabella ma NON devono entrare nel costo corrente del prodotto.
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
    -- Solo le parti del piano ATTIVO (vedi nota in material_cost).
    JOIN inventory."ProductPartPlan" ap
      ON ap.id = pp."planId" AND ap.status = 'ACTIVE'
    WHERE pp."sourceType" = 'BUY'
    GROUP BY pp."productId"
),
-- Worst case: lo SKU con la variante di BOM più costosa rappresenta il prodotto.
worst_variant AS (
    SELECT DISTINCT ON (bv.product_id)
        bv.product_id,
        bv.sku_id,
        bv.components_cost,
        bv.packaging_cost,
        bv.utilities_cost
    FROM inventory_views.v_product_bom_variant_cost bv
    WHERE bv.sku_id IS NOT NULL
    ORDER BY bv.product_id, bv.variant_cost DESC, bv.sku_id
),
-- Fallback per i prodotti senza SKU: solo le righe condivise.
shared_variant AS (
    SELECT
        bv.product_id,
        bv.components_cost,
        bv.packaging_cost,
        bv.utilities_cost
    FROM inventory_views.v_product_bom_variant_cost bv
    WHERE bv.sku_id IS NULL
),
sku_stats AS (
    SELECT
        bv.product_id,
        COUNT(*)::INT AS sku_variant_count,
        BOOL_OR(bv.has_dedicated_bom) AS has_sku_specific_bom
    FROM inventory_views.v_product_bom_variant_cost bv
    WHERE bv.sku_id IS NOT NULL
    GROUP BY bv.product_id
)
SELECT
    pr.id AS product_id,
    COALESCE(mc.materials_cost, 0)::DECIMAL(12,4) AS materials_cost,
    COALESCE(bp.buy_parts_cost, 0)::DECIMAL(12,4) AS buy_parts_cost,
    COALESCE(wv.components_cost, sv.components_cost, 0)::DECIMAL(12,4) AS components_cost,
    COALESCE(wv.packaging_cost, sv.packaging_cost, 0)::DECIMAL(12,4) AS packaging_cost,
    COALESCE(wv.utilities_cost, sv.utilities_cost, 0)::DECIMAL(12,4) AS utilities_cost,
    (
        COALESCE(mc.materials_cost, 0)
      + COALESCE(bp.buy_parts_cost, 0)
      + COALESCE(wv.components_cost, sv.components_cost, 0)
      + COALESCE(wv.packaging_cost, sv.packaging_cost, 0)
      + COALESCE(wv.utilities_cost, sv.utilities_cost, 0)
    )::DECIMAL(12,4) AS raw_material_cost,
    -- Colonne in coda: aggiunte con CREATE OR REPLACE, le view dipendenti restano valide.
    wv.sku_id AS worst_case_sku_id,
    COALESCE(ss.sku_variant_count, 0) AS sku_variant_count,
    COALESCE(ss.has_sku_specific_bom, FALSE) AS has_sku_specific_bom
FROM inventory."Product" pr
LEFT JOIN material_cost mc ON mc.product_id = pr.id
LEFT JOIN buy_parts_cost bp ON bp.product_id = pr.id
LEFT JOIN worst_variant wv ON wv.product_id = pr.id
LEFT JOIN shared_variant sv ON sv.product_id = pr.id
LEFT JOIN sku_stats ss ON ss.product_id = pr.id;

-- ----------------------------------------------------------------------------
-- 3. Breakdown costo materie prime per SKU
-- Materiali (parti MAKE) e parti BUY arrivano dalla view prodotto: sono comuni a
-- tutti gli SKU perché `ProductPart`/`ProductPartMaterial` non hanno `skuId`.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE VIEW inventory_views.v_sku_cost_breakdown AS
SELECT
    s.id AS sku_id,
    s.code AS sku_code,
    s."productId" AS product_id,
    p.name AS product_name,
    s.channel::TEXT AS channel,

    -- Comuni a tutti gli SKU del prodotto (nessuna dimensione SKU nella BOM parti)
    pcb.materials_cost,
    pcb.buy_parts_cost,

    -- Specifici dello SKU
    bv.components_cost,
    bv.packaging_cost,
    bv.utilities_cost,
    (
        pcb.materials_cost
      + pcb.buy_parts_cost
      + bv.variant_cost
    )::DECIMAL(12,4) AS raw_material_cost,
    bv.dedicated_cost,
    bv.has_dedicated_bom,

    -- Confronto con il costo prodotto (worst case): >0 solo per lo SKU peggiore
    pcb.raw_material_cost AS product_raw_material_cost,
    (
        pcb.materials_cost
      + pcb.buy_parts_cost
      + bv.variant_cost
      - pcb.raw_material_cost
    )::DECIMAL(12,4) AS raw_material_cost_delta
FROM inventory."Sku" s
JOIN inventory."Product" p ON p.id = s."productId"
JOIN inventory_views.v_product_bom_variant_cost bv
  ON bv.product_id = s."productId" AND bv.sku_id = s.id
JOIN inventory_views.v_product_cost_breakdown pcb ON pcb.product_id = s."productId";

-- ----------------------------------------------------------------------------
-- 4. Pricing summary per SKU
-- Manodopera ed energia non hanno dimensione SKU (si assembla e si stampa lo
-- stesso prodotto qualunque sia il canale): sono ereditate dal prodotto.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE VIEW inventory_views.v_sku_pricing_summary AS
WITH settings_margin AS (
    SELECT
        CASE
            WHEN value::text ~ '^[0-9.]+$' THEN (value::text)::NUMERIC
            WHEN jsonb_typeof(value::jsonb) = 'number' THEN (value::text)::NUMERIC
            WHEN (value::jsonb) ? 'value' THEN (value::jsonb->>'value')::NUMERIC
            ELSE 0.3
        END AS profit_margin
    FROM inventory."Settings"
    WHERE name = 'PROFIT_MARGIN'
    LIMIT 1
)
SELECT
    cb.sku_id,
    cb.sku_code,
    cb.product_id,
    cb.product_name,
    cb.channel,

    -- Materie prime per SKU
    cb.materials_cost,
    cb.buy_parts_cost,
    cb.components_cost,
    cb.packaging_cost,
    cb.utilities_cost,
    cb.raw_material_cost,
    cb.dedicated_cost,
    cb.has_dedicated_bom,

    -- Manodopera ed energia: ereditate dal prodotto
    pps.operational_cost,
    pps.historical_operational_cost,
    pps.recent_operational_cost,
    pps.has_labor_data,
    pps.effective_labor_seconds_per_unit,
    pps.median_minutes_per_unit,
    pps.sample_size_total,
    pps.recent_sample_size,
    pps.electricity_cost,
    pps.energy_cost_per_kwh,
    pps.total_energy_kwh,
    pps.print_minutes,

    -- Totali per SKU
    CAST(
        cb.raw_material_cost + pps.operational_cost + pps.electricity_cost
    AS DECIMAL(12,4)) AS total_cost,
    CAST(
        cb.raw_material_cost + pps.operational_cost + pps.electricity_cost
    AS DECIMAL(12,4)) AS production_cost,
    CAST(
        (cb.raw_material_cost + pps.operational_cost + pps.electricity_cost)
        * (1 + COALESCE((SELECT profit_margin FROM settings_margin), 0.3))
    AS DECIMAL(12,2)) AS suggested_price,
    pps."sellingPrice",
    pps.effective_selling_price,

    -- Confronto con il costo prodotto (worst case)
    pps.total_cost AS product_total_cost,
    CAST(
        cb.raw_material_cost + pps.operational_cost + pps.electricity_cost
        - pps.total_cost
    AS DECIMAL(12,4)) AS total_cost_delta
FROM inventory_views.v_sku_cost_breakdown cb
JOIN inventory_views.v_product_pricing_summary pps ON pps.product_id = cb.product_id;
