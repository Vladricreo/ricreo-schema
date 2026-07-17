-- Fix: domanda Material riservata in bobine con CEIL (FLOOR azzerava fabbisogni < 1 bobina).
CREATE OR REPLACE VIEW inventory_views.v_item_reserved_stock AS
WITH active_orders AS (
  SELECT id AS product_order_id
  FROM inventory."ProductOrder"
  WHERE "productionStatus" IN ('READY_TO_PRODUCE', 'PRODUCING', 'NEED_SUPPLIES')
),
required_agg AS (
  SELECT
    r.item_id,
    r.kind,
    SUM(r.quantity_needed_remaining) AS total_needed
  FROM inventory_views.v_product_order_required_items r
  JOIN active_orders ao ON ao.product_order_id = r.product_order_id
  GROUP BY r.item_id, r.kind
),
item_reserved AS (
  SELECT
    ra.item_id,
    CASE
      WHEN ra.kind = 'Material' THEN
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
