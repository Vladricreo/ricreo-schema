-- InventoryLot ISO 9001:
-- 1) Estende update_stock_cache: manufacturedAt / receivedAt / CLOSED automatici
-- 2) Backfill date e stati sui lotti esistenti

CREATE OR REPLACE FUNCTION inventory.update_stock_cache()
RETURNS TRIGGER AS $$
DECLARE
  v_delta INT;
  v_is_positive BOOLEAN;
  v_sku_delta INT;
  v_lot_stockable INT;
  v_lot_has_inbound BOOLEAN;
BEGIN
  v_is_positive := NEW.type IN ('PRODUZIONE', 'ACQUISTO', 'RIMBORSO_PRODUZIONE', 'RIMBORSO_USO', 'CORRECTION_UP', 'STAGE_IN', 'RESO_IN');
  v_delta := CASE WHEN v_is_positive THEN NEW.quantity ELSE -NEW.quantity END;

  IF NEW."itemId" IS NOT NULL THEN
    UPDATE inventory."Item"
    SET "inStock" = GREATEST(0, "inStock" + v_delta)
    WHERE id = NEW."itemId";
  END IF;

  IF NEW."assemblyStageId" IS NOT NULL THEN
    UPDATE inventory."AssemblyStage"
    SET instock = GREATEST(0, COALESCE(instock, 0) + (
      CASE
        WHEN NEW.type = 'STAGE_IN' THEN NEW.quantity
        WHEN NEW.type = 'STAGE_OUT' THEN -NEW.quantity
        ELSE 0
      END
    ))
    WHERE id = NEW."assemblyStageId";
  END IF;

  IF NEW."productPartId" IS NOT NULL THEN
    UPDATE inventory."ProductPart"
    SET "inStock" = GREATEST(0, "inStock" + v_delta)
    WHERE id = NEW."productPartId";
  END IF;

  IF NEW."skuId" IS NOT NULL THEN
    v_sku_delta := CASE
      WHEN NEW.type IN ('PRODUZIONE', 'ACQUISTO', 'RIMBORSO_PRODUZIONE', 'RIMBORSO_USO', 'CORRECTION_UP', 'RESO_IN') THEN NEW.quantity
      WHEN NEW.type IN ('VENDITA', 'TRASH', 'CORRECTION_DOWN') THEN -NEW.quantity
      ELSE 0
    END;

    IF v_sku_delta != 0 THEN
      UPDATE inventory."Sku"
      SET "currentStock" = GREATEST(0, COALESCE("currentStock", 0) + v_sku_delta)
      WHERE id = NEW."skuId";
    END IF;
  END IF;

  -- InventoryLot: date ISO + chiusura automatica
  IF NEW."lotId" IS NOT NULL THEN
    IF NEW.type = 'PRODUZIONE' THEN
      UPDATE inventory."InventoryLot"
      SET "manufacturedAt" = COALESCE("manufacturedAt", NEW.date),
          "updatedAt" = NOW()
      WHERE id = NEW."lotId";
    END IF;

    IF NEW.type = 'ACQUISTO' THEN
      UPDATE inventory."InventoryLot"
      SET "receivedAt" = COALESCE("receivedAt", NEW.date),
          "updatedAt" = NOW()
      WHERE id = NEW."lotId";
    END IF;

    SELECT
      l."initialQuantity" + COALESCE((
        SELECT SUM(CASE
          WHEN m.type IN (
            'PRODUZIONE', 'ACQUISTO', 'RIMBORSO_PRODUZIONE',
            'RIMBORSO_USO', 'CORRECTION_UP', 'RESO_IN'
          ) THEN m.quantity
          WHEN m.type IN (
            'USO', 'TRASH', 'VENDITA', 'CORRECTION_DOWN'
          ) THEN -m.quantity
          ELSE 0
        END)
        FROM inventory."Movement" m
        WHERE m."lotId" = NEW."lotId"
      ), 0),
      (l."initialQuantity" > 0) OR EXISTS (
        SELECT 1
        FROM inventory."Movement" m2
        WHERE m2."lotId" = NEW."lotId"
          AND m2.type IN (
            'PRODUZIONE', 'ACQUISTO', 'RIMBORSO_PRODUZIONE',
            'RIMBORSO_USO', 'CORRECTION_UP', 'RESO_IN'
          )
      )
    INTO v_lot_stockable, v_lot_has_inbound
    FROM inventory."InventoryLot" l
    WHERE l.id = NEW."lotId";

    IF COALESCE(v_lot_has_inbound, FALSE)
       AND COALESCE(v_lot_stockable, 0) <= 0 THEN
      UPDATE inventory."InventoryLot"
      SET status = 'CLOSED',
          "updatedAt" = NOW()
      WHERE id = NEW."lotId"
        AND status IS DISTINCT FROM 'CLOSED';
    ELSIF COALESCE(v_lot_stockable, 0) > 0 THEN
      UPDATE inventory."InventoryLot"
      SET status = 'OPEN',
          "updatedAt" = NOW()
      WHERE id = NEW."lotId"
        AND status IS DISTINCT FROM 'OPEN';
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Backfill receivedAt dal primo ACQUISTO
UPDATE inventory."InventoryLot" l
SET "receivedAt" = sub.first_in,
    "updatedAt" = NOW()
FROM (
  SELECT m."lotId", MIN(m.date) AS first_in
  FROM inventory."Movement" m
  WHERE m.type = 'ACQUISTO'
    AND m."lotId" IS NOT NULL
  GROUP BY m."lotId"
) sub
WHERE l.id = sub."lotId"
  AND (l."receivedAt" IS NULL OR l."receivedAt" > sub.first_in);

-- manufacturedAt: solo da PRODUZIONE (pulisce timestamp WIP prematuri)
UPDATE inventory."InventoryLot" l
SET "manufacturedAt" = NULL,
    "updatedAt" = NOW()
WHERE NOT EXISTS (
  SELECT 1
  FROM inventory."Movement" m
  WHERE m."lotId" = l.id
    AND m.type = 'PRODUZIONE'
);

UPDATE inventory."InventoryLot" l
SET "manufacturedAt" = sub.first_prod,
    "updatedAt" = NOW()
FROM (
  SELECT m."lotId", MIN(m.date) AS first_prod
  FROM inventory."Movement" m
  WHERE m.type = 'PRODUZIONE'
    AND m."lotId" IS NOT NULL
  GROUP BY m."lotId"
) sub
WHERE l.id = sub."lotId";

-- Backfill status OPEN/CLOSED su stock tracciabile (ignora STAGE_*)
WITH lot_stock AS (
  SELECT
    l.id AS lot_id,
    (
      l."initialQuantity" + COALESCE((
        SELECT SUM(CASE
          WHEN m.type IN (
            'PRODUZIONE', 'ACQUISTO', 'RIMBORSO_PRODUZIONE',
            'RIMBORSO_USO', 'CORRECTION_UP', 'RESO_IN'
          ) THEN m.quantity
          WHEN m.type IN (
            'USO', 'TRASH', 'VENDITA', 'CORRECTION_DOWN'
          ) THEN -m.quantity
          ELSE 0
        END)
        FROM inventory."Movement" m
        WHERE m."lotId" = l.id
      ), 0)
    )::INT AS stockable,
    (
      (l."initialQuantity" > 0) OR EXISTS (
        SELECT 1
        FROM inventory."Movement" m2
        WHERE m2."lotId" = l.id
          AND m2.type IN (
            'PRODUZIONE', 'ACQUISTO', 'RIMBORSO_PRODUZIONE',
            'RIMBORSO_USO', 'CORRECTION_UP', 'RESO_IN'
          )
      )
    ) AS has_inbound
  FROM inventory."InventoryLot" l
)
UPDATE inventory."InventoryLot" l
SET status = CASE
      WHEN ls.has_inbound AND ls.stockable <= 0 THEN 'CLOSED'::inventory."InventoryLotStatus"
      WHEN ls.stockable > 0 THEN 'OPEN'::inventory."InventoryLotStatus"
      ELSE l.status
    END,
    "updatedAt" = NOW()
FROM lot_stock ls
WHERE l.id = ls.lot_id
  AND l.status IS DISTINCT FROM (
    CASE
      WHEN ls.has_inbound AND ls.stockable <= 0 THEN 'CLOSED'::inventory."InventoryLotStatus"
      WHEN ls.stockable > 0 THEN 'OPEN'::inventory."InventoryLotStatus"
      ELSE l.status
    END
  );
