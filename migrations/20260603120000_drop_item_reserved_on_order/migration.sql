-- Rimuove le colonne cache deprecate `Item.reserved` e `Item.onOrder`.
--
-- Contesto:
--  * `reserved`: la quantità riservata è deprecata; il valore "vero" è calcolato dinamicamente
--    dalla view `inventory_views.v_item_reserved_stock` (ordini di produzione attivi) e NON dipende
--    da questa colonna. La colonna era dormiente (il trigger non la aggiornava più).
--  * `onOrder`: la quantità "in ordine" è ora derivata dalle PurchaseOrderLine (TO_ORDER + ORDERED),
--    cioè dalla pipeline degli ordini d'acquisto (Single Source of Truth = inventory orders).
--
-- Prima del DROP COLUMN dobbiamo ridefinire le view che referenziano le colonne, altrimenti
-- Postgres blocca la rimozione (dipendenze).

-- ============================================================================
-- 1) v_product_order_required_items: `quantity_available` non sottrae più `reserved`.
--    CREATE OR REPLACE mantiene le stesse colonne di output (non rompe le view dipendenti).
-- ============================================================================
CREATE OR REPLACE VIEW inventory_views.v_product_order_required_items AS
WITH order_base AS (
  SELECT
    o.id AS product_order_id,
    o.number AS product_order_number,
    o."productId" AS product_id,
    o."skuId" AS sku_id,
    o."assemblyOrderId" AS assembly_order_id,
    ao.number AS assembly_order_number,
    o."quantityToProduce" AS quantity_to_produce,
    GREATEST(o."quantityToProduce" - o."quantityProduced", 0) AS quantity_remaining,
    (o."quantityToProduce" = 0) AS is_parts_only
  FROM inventory."ProductOrder" o
  LEFT JOIN inventory."AssemblyOrder" ao ON ao.id = o."assemblyOrderId"
),
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
    NULL::UUID AS product_part_id
  FROM order_base ob
  JOIN inventory."ProductToComponent" c
    ON c."productId" = ob.product_id
   AND c.priority = 0
   AND (c."skuId" IS NULL OR c."skuId" = ob.sku_id)
  JOIN inventory_views.v_item_spec_resolved ri
    ON ri.spec_id = c."itemSpecId"
  WHERE ob.quantity_to_produce > 0
),
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
    NULL::UUID AS product_part_id
  FROM order_base ob
  JOIN inventory."ProductToPackage" p
    ON p."productId" = ob.product_id
   AND p.priority = 0
   AND (p."skuId" IS NULL OR p."skuId" = ob.sku_id)
  JOIN inventory_views.v_item_spec_resolved ri
    ON ri.spec_id = p."itemSpecId"
  WHERE ob.quantity_to_produce > 0
),
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
    NULL::UUID AS product_part_id
  FROM order_base ob
  JOIN inventory."ProductToUtility" u
    ON u."productId" = ob.product_id
   AND u.priority = 0
   AND (u."skuId" IS NULL OR u."skuId" = ob.sku_id)
  JOIN inventory_views.v_item_spec_resolved ri
    ON ri.spec_id = u."itemSpecId"
  WHERE ob.quantity_to_produce > 0
),
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
    rp.product_part_id
  FROM required_parts rp
  JOIN order_base ob ON ob.product_order_id = rp.product_order_id
  JOIN inventory."ProductPart" pp ON pp.id = rp.product_part_id
  JOIN inventory."ProductPartMaterial" mb
    ON mb."productPartId" = rp.product_part_id
   AND mb.priority = 0
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
  COALESCE(l.quantity_needed, l.quantity_needed_grams, 0)::NUMERIC AS quantity_needed,
  -- Disponibilità: pezzi = GREATEST(inStock, 0); Material → grammi (× peso bobina).
  -- Nota: la quantità riservata è deprecata e NON viene sottratta dalla disponibilità.
  CASE
    WHEN l.kind = 'Material' THEN
      GREATEST(COALESCE(i."inStock", 0), 0)::NUMERIC * (COALESCE(i.weight, sw.weight, 0)::NUMERIC * 1000)
    ELSE
      GREATEST(COALESCE(i."inStock", 0), 0)::NUMERIC
  END AS quantity_available,
  i.name AS item_name,
  i.sku AS item_sku,
  i."imageUrl" AS item_image_url,
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
  lot.code AS suggested_lot_code,
  COALESCE(l.quantity_needed_remaining, l.quantity_needed_grams_remaining, 0)::NUMERIC AS quantity_needed_remaining
FROM (
  SELECT * FROM component_lines
  UNION ALL SELECT * FROM package_lines
  UNION ALL SELECT * FROM utility_lines
  UNION ALL SELECT * FROM material_lines
) l
JOIN inventory."Item" i ON i.id = l.item_id
LEFT JOIN inventory."StandardWeight" sw ON sw.id = i."standardWeightId"
LEFT JOIN LATERAL (
  SELECT il.code
  FROM inventory."InventoryLot" il
  WHERE il."itemId" = i.id
    AND il.status = 'OPEN'
  ORDER BY il."createdAt" ASC
  LIMIT 1
) lot ON true;

-- ============================================================================
-- 2) v_dashboard_low_stock_items: disponibile = inStock; on_order derivato dalla pipeline
--    PurchaseOrderLine (TO_ORDER + ORDERED).
-- ============================================================================
CREATE OR REPLACE VIEW "inventory_views"."v_dashboard_low_stock_items" AS
SELECT
  i."sku" AS sku,
  i."inStock" AS available,
  i."minStock" AS min_stock,
  COALESCE((
    SELECT SUM(pol.quantity)
    FROM "inventory"."PurchaseOrderLine" pol
    JOIN "inventory"."PurchaseOrder" po ON po.id = pol."orderId"
    WHERE pol."itemId" = i.id
      AND po.status IN ('TO_ORDER', 'ORDERED')
  ), 0)::INT AS on_order,
  GREATEST(i."minStock" - i."inStock", 0) AS deficit,
  CASE
    WHEN i."inStock" <= 0 THEN 'CRITICAL'
    WHEN i."inStock" <= i."minStock" THEN 'WARNING'
    ELSE 'OK'
  END AS severity
FROM "inventory"."Item" i
WHERE i."type" != 'TOOL'
  AND i."minStock" > 0
  AND i."inStock" <= i."minStock"
ORDER BY
  CASE
    WHEN i."inStock" <= 0 THEN 0
    ELSE 1
  END,
  i."inStock" ASC;

-- ============================================================================
-- 3) Drop delle colonne cache deprecate.
-- ============================================================================
ALTER TABLE "inventory"."Item" DROP COLUMN IF EXISTS "reserved";
ALTER TABLE "inventory"."Item" DROP COLUMN IF EXISTS "onOrder";
