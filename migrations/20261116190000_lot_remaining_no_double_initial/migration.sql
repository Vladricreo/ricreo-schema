-- S-304 (16/11/2026): residuo lotto senza doppio conteggio di initialQuantity.
--
-- Prima residuo = initialQuantity + ingressi - uscite, sia nella vista
-- `v_inventory_lot_remaining` sia nel trigger che apre/chiude i lotti
-- (`update_stock_cache` / `revert_stock_cache`). Ma quasi tutti i lotti nascono
-- con initialQuantity E con un movimento d'ingresso per gli stessi pezzi
-- (scarico stampante Print Farm: initialQuantity = pezzi attesi; ricezione
-- acquisto; ingresso SKU). Il carico contava due volte: 2.794 lotti di
-- produzione, 134 d'acquisto e 16 altri restavano APERTI pur vuoti, con circa
-- 254.000 pezzi inesistenti sui lotti aperti; «Annulla ricezione» leggeva un
-- residuo gonfiato.
--
-- Regola nuova (la stessa del consumo FIFO in `movement-service.ts`):
--   residuo = (initialQuantity solo se il lotto NON ha movimenti d'ingresso)
--             + ingressi - uscite.
-- initialQuantity resta la giacenza dei lotti senza ingressi (lotti sintetici
-- ADJUSTMENT creati dal FIFO, saldi legacy).
--
-- Le giacenze di Item / ProductPart / Sku NON cambiano: si calcolano solo dai
-- movimenti. Cambiano il residuo dei lotti e il loro stato OPEN/CLOSED.
-- Sorgente: `client/prisma/custom_migrations/sql/stock_views_and_triggers.sql`
-- (Ricreo-Inventory), da cui sono copiati i tre blocchi sotto.

-- 1) Vista residuo lotto.
CREATE OR REPLACE VIEW inventory_views.v_inventory_lot_remaining AS
SELECT 
  l.id AS lot_id,
  l.code AS lot_code,
  l.number AS lot_number,
  l."originType" AS origin_type,
  l.status AS lot_status,
  l."itemId",
  l."productPartId",
  l."productId",
  l."productionLotId",
  l."initialQuantity",
  l."receivedAt",
  l."manufacturedAt",
  l."createdAt",
  -- Calcola i movimenti IN per questo lotto
  COALESCE((
    SELECT SUM(m.quantity)
    FROM inventory."Movement" m
    WHERE m."lotId" = l.id
      AND m.type IN ('PRODUZIONE', 'ACQUISTO', 'RIMBORSO_PRODUZIONE', 'RIMBORSO_USO', 'CORRECTION_UP', 'STAGE_IN', 'RESO_IN')
  ), 0)::INT AS total_in,
  -- Calcola i movimenti OUT per questo lotto
  COALESCE((
    SELECT SUM(m.quantity)
    FROM inventory."Movement" m
    WHERE m."lotId" = l.id
      AND m.type IN ('USO', 'TRASH', 'VENDITA', 'CORRECTION_DOWN', 'STAGE_OUT')
  ), 0)::INT AS total_out,
  -- Quantità residua = base + IN - OUT.
  -- base = initialQuantity SOLO se il lotto non ha ingressi registrati come movimento
  -- (lotti sintetici ADJUSTMENT del FIFO, saldi legacy). Quando il carico è anche un
  -- movimento (scarico stampante, ricezione acquisto, ingresso SKU) initialQuantity
  -- è lo stesso carico (o i pezzi attesi): sommarlo lo contava due volte (16/11/2026).
  -- Stessa regola del FIFO (movement-service) e del trigger update_stock_cache.
  ((CASE WHEN EXISTS (
    SELECT 1 FROM inventory."Movement" mi
    WHERE mi."lotId" = l.id
      AND mi.type IN ('PRODUZIONE', 'ACQUISTO', 'RIMBORSO_PRODUZIONE', 'RIMBORSO_USO', 'CORRECTION_UP', 'RESO_IN')
  ) THEN 0 ELSE l."initialQuantity" END) + COALESCE((
    SELECT SUM(CASE 
      WHEN m.type IN ('PRODUZIONE', 'ACQUISTO', 'RIMBORSO_PRODUZIONE', 'RIMBORSO_USO', 'CORRECTION_UP', 'STAGE_IN', 'RESO_IN') THEN m.quantity
      WHEN m.type IN ('USO', 'TRASH', 'VENDITA', 'CORRECTION_DOWN', 'STAGE_OUT') THEN -m.quantity
      ELSE 0
    END)
    FROM inventory."Movement" m
    WHERE m."lotId" = l.id
  ), 0))::INT AS remaining_quantity
FROM inventory."InventoryLot" l;

-- 2) Trigger AFTER INSERT su Movement: stato lotto con la nuova regola.
CREATE OR REPLACE FUNCTION inventory.update_stock_cache()
RETURNS TRIGGER AS $$
DECLARE
  v_delta INT;
  v_is_positive BOOLEAN;
  v_sku_delta INT;
  v_lot_stockable INT;
  v_lot_has_inbound BOOLEAN;
BEGIN
  -- Determina se il movimento è positivo o negativo
  v_is_positive := NEW.type IN ('PRODUZIONE', 'ACQUISTO', 'RIMBORSO_PRODUZIONE', 'RIMBORSO_USO', 'CORRECTION_UP', 'STAGE_IN', 'RESO_IN');
  v_delta := CASE WHEN v_is_positive THEN NEW.quantity ELSE -NEW.quantity END;

  -- ========================================
  -- Aggiorna Item.inStock
  -- ========================================
  IF NEW."itemId" IS NOT NULL THEN
    UPDATE inventory."Item" 
    SET "inStock" = GREATEST(0, "inStock" + v_delta)
    WHERE id = NEW."itemId";
  END IF;
  
  -- ========================================
  -- Aggiorna AssemblyStage.instock
  -- ========================================
  IF NEW."assemblyStageId" IS NOT NULL THEN
    -- Deve restare allineato a `v_assembly_stage_stock`, altrimenti
    -- `reconcile_all_stock()` sovrascrive il valore in cache.
    -- TRASH scarica il WIP scartato; CORRECTION_* applica le rettifiche di fase.
    UPDATE inventory."AssemblyStage" 
    -- Nota: `instock` può essere NULL su righe legacy; GREATEST(0, NULL) => NULL.
    -- Usiamo COALESCE per garantire aggiornamenti corretti.
    SET instock = GREATEST(0, COALESCE(instock, 0) + (
      CASE 
        WHEN NEW.type = 'STAGE_IN' THEN NEW.quantity
        WHEN NEW.type = 'STAGE_OUT' THEN -NEW.quantity
        WHEN NEW.type = 'TRASH' THEN -NEW.quantity
        WHEN NEW.type = 'CORRECTION_UP' THEN NEW.quantity
        WHEN NEW.type = 'CORRECTION_DOWN' THEN -NEW.quantity
        ELSE 0
      END
    ))
    WHERE id = NEW."assemblyStageId";
  END IF;
  
  -- ========================================
  -- Aggiorna ProductPart.inStock
  -- ========================================
  -- Nessun GREATEST(0, ...): con il limite a 0 un'uscita oltre la giacenza
  -- veniva "persa" e il rientro successivo gonfiava `inStock` rispetto ai
  -- movimenti. La differenza compariva come parti loose inesistenti
  -- (loose = inStock - quantità in odette). Resta allineato a
  -- `v_product_part_stock` e a `reconcile_all_stock()`, che non limitano.
  IF NEW."productPartId" IS NOT NULL THEN
    UPDATE inventory."ProductPart"
    SET "inStock" = "inStock" + v_delta
    WHERE id = NEW."productPartId";
  END IF;
  
  -- ========================================
  -- Aggiorna Sku.currentStock
  -- ========================================
  -- I movimenti di un articolo o di una parte portano lo SKU solo come contesto
  -- (es. RIMBORSO_USO della scatola di una spedizione): non toccano lo stock SKU.
  IF NEW."skuId" IS NOT NULL AND NEW."itemId" IS NULL AND NEW."productPartId" IS NULL THEN
    -- Per coerenza con v_sku_stock: i movimenti STAGE_IN/STAGE_OUT (WIP) non devono impattare lo stock SKU,
    -- anche se hanno skuId valorizzato.
    v_sku_delta := CASE
      WHEN NEW.type IN ('PRODUZIONE', 'ACQUISTO', 'RIMBORSO_PRODUZIONE', 'RIMBORSO_USO', 'CORRECTION_UP', 'RESO_IN') THEN NEW.quantity
      WHEN NEW.type IN ('VENDITA', 'TRASH', 'CORRECTION_DOWN') THEN -NEW.quantity
      ELSE 0
    END;

    -- Nessun GREATEST(0, ...) (come per ProductPart): un'uscita oltre la giacenza
    -- (es. scatole FBA spedite prima della PRODUZIONE) veniva "persa" e il carico
    -- successivo creava stock fantasma. Resta allineato a `v_sku_stock`.
    IF v_sku_delta != 0 THEN
    UPDATE inventory."Sku"
      SET "currentStock" = COALESCE("currentStock", 0) + v_sku_delta
      WHERE id = NEW."skuId";
    END IF;
  END IF;
  
  -- ========================================
  -- NOTA: OdetteContent.quantity viene gestito manualmente nel codice applicativo
  -- per permettere create/delete delle righe (il trigger non può farlo).
  -- In futuro si potrebbe migrare a trigger-based con cleanup separato.
  -- ========================================

  -- ========================================
  -- InventoryLot (ISO 9001): date + chiusura automatica
  -- - manufacturedAt: prima PRODUZIONE (rilascio prodotto finito / parte prodotta)
  -- - receivedAt: primo ACQUISTO
  -- - status CLOSED quando lo stock tracciabile del lotto è esaurito
  --   (STAGE_IN/STAGE_OUT sono WIP e non contano per OPEN/CLOSED)
  -- ========================================
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
      -- initialQuantity conta solo se il lotto non ha ingressi registrati come
      -- movimento (lotti sintetici/legacy): altrimenti è lo stesso carico e lo
      -- contava due volte, tenendo APERTI lotti vuoti (16/11/2026).
      (CASE WHEN EXISTS (
        SELECT 1
        FROM inventory."Movement" mi
        WHERE mi."lotId" = NEW."lotId"
          AND mi.type IN (
            'PRODUZIONE', 'ACQUISTO', 'RIMBORSO_PRODUZIONE',
            'RIMBORSO_USO', 'CORRECTION_UP', 'RESO_IN'
          )
      ) THEN 0 ELSE l."initialQuantity" END) + COALESCE((
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

-- 3) Trigger AFTER DELETE su Movement: stessa regola.
CREATE OR REPLACE FUNCTION inventory.revert_stock_cache()
RETURNS TRIGGER AS $$
DECLARE
  v_delta INT;
  v_sku_delta INT;
  v_lot_stockable INT;
  v_lot_has_inbound BOOLEAN;
BEGIN
  -- Delta inverso rispetto all'INSERT.
  v_delta := CASE
    WHEN OLD.type IN ('PRODUZIONE', 'ACQUISTO', 'RIMBORSO_PRODUZIONE', 'RIMBORSO_USO', 'CORRECTION_UP', 'STAGE_IN', 'RESO_IN')
      THEN -OLD.quantity
    ELSE OLD.quantity
  END;

  IF OLD."itemId" IS NOT NULL THEN
    UPDATE inventory."Item"
    SET "inStock" = GREATEST(0, "inStock" + v_delta)
    WHERE id = OLD."itemId";
  END IF;

  IF OLD."assemblyStageId" IS NOT NULL THEN
    UPDATE inventory."AssemblyStage"
    SET instock = GREATEST(0, COALESCE(instock, 0) - (
      CASE
        WHEN OLD.type = 'STAGE_IN' THEN OLD.quantity
        WHEN OLD.type = 'STAGE_OUT' THEN -OLD.quantity
        WHEN OLD.type = 'TRASH' THEN -OLD.quantity
        WHEN OLD.type = 'CORRECTION_UP' THEN OLD.quantity
        WHEN OLD.type = 'CORRECTION_DOWN' THEN -OLD.quantity
        ELSE 0
      END
    ))
    WHERE id = OLD."assemblyStageId";
  END IF;

  IF OLD."productPartId" IS NOT NULL THEN
    UPDATE inventory."ProductPart"
    SET "inStock" = "inStock" + v_delta
    WHERE id = OLD."productPartId";
  END IF;

  IF OLD."skuId" IS NOT NULL AND OLD."itemId" IS NULL AND OLD."productPartId" IS NULL THEN
    v_sku_delta := CASE
      WHEN OLD.type IN ('PRODUZIONE', 'ACQUISTO', 'RIMBORSO_PRODUZIONE', 'RIMBORSO_USO', 'CORRECTION_UP', 'RESO_IN') THEN -OLD.quantity
      WHEN OLD.type IN ('VENDITA', 'TRASH', 'CORRECTION_DOWN') THEN OLD.quantity
      ELSE 0
    END;

    IF v_sku_delta != 0 THEN
      UPDATE inventory."Sku"
      SET "currentStock" = COALESCE("currentStock", 0) + v_sku_delta
      WHERE id = OLD."skuId";
    END IF;
  END IF;

  -- Stato lotto: AFTER DELETE, il movimento non è più nella somma.
  IF OLD."lotId" IS NOT NULL THEN
    SELECT
      -- initialQuantity conta solo se il lotto non ha ingressi registrati come
      -- movimento (lotti sintetici/legacy): altrimenti è lo stesso carico e lo
      -- contava due volte, tenendo APERTI lotti vuoti (16/11/2026).
      (CASE WHEN EXISTS (
        SELECT 1
        FROM inventory."Movement" mi
        WHERE mi."lotId" = OLD."lotId"
          AND mi.type IN (
            'PRODUZIONE', 'ACQUISTO', 'RIMBORSO_PRODUZIONE',
            'RIMBORSO_USO', 'CORRECTION_UP', 'RESO_IN'
          )
      ) THEN 0 ELSE l."initialQuantity" END) + COALESCE((
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
        WHERE m."lotId" = OLD."lotId"
      ), 0),
      (l."initialQuantity" > 0) OR EXISTS (
        SELECT 1
        FROM inventory."Movement" m2
        WHERE m2."lotId" = OLD."lotId"
          AND m2.type IN (
            'PRODUZIONE', 'ACQUISTO', 'RIMBORSO_PRODUZIONE',
            'RIMBORSO_USO', 'CORRECTION_UP', 'RESO_IN'
          )
      )
    INTO v_lot_stockable, v_lot_has_inbound
    FROM inventory."InventoryLot" l
    WHERE l.id = OLD."lotId";

    IF COALESCE(v_lot_has_inbound, FALSE)
       AND COALESCE(v_lot_stockable, 0) <= 0 THEN
      UPDATE inventory."InventoryLot"
      SET status = 'CLOSED',
          "updatedAt" = NOW()
      WHERE id = OLD."lotId"
        AND status IS DISTINCT FROM 'CLOSED';
    ELSIF COALESCE(v_lot_stockable, 0) > 0 THEN
      UPDATE inventory."InventoryLot"
      SET status = 'OPEN',
          "updatedAt" = NOW()
      WHERE id = OLD."lotId"
        AND status IS DISTINCT FROM 'OPEN';
    END IF;
  END IF;

  RETURN OLD;
END;
$$ LANGUAGE plpgsql;

-- 4) Ricalcolo una tantum dello stato dei lotti con la nuova regola.
--    Stessa logica del trigger: si chiude solo un lotto «stoccabile»
--    (con ingressi o initialQuantity > 0) rimasto a zero; si riapre se > 0.
--    `updatedAt` non si tocca: non è una modifica fatta da qualcuno.
WITH stock AS (
  SELECT
    l.id,
    l.status,
    (CASE WHEN EXISTS (
      SELECT 1 FROM inventory."Movement" mi
      WHERE mi."lotId" = l.id
        AND mi.type IN ('PRODUZIONE', 'ACQUISTO', 'RIMBORSO_PRODUZIONE', 'RIMBORSO_USO', 'CORRECTION_UP', 'RESO_IN')
    ) THEN 0 ELSE l."initialQuantity" END) + COALESCE((
      SELECT SUM(CASE
        WHEN m.type IN ('PRODUZIONE', 'ACQUISTO', 'RIMBORSO_PRODUZIONE', 'RIMBORSO_USO', 'CORRECTION_UP', 'RESO_IN') THEN m.quantity
        WHEN m.type IN ('USO', 'TRASH', 'VENDITA', 'CORRECTION_DOWN') THEN -m.quantity
        ELSE 0
      END)
      FROM inventory."Movement" m
      WHERE m."lotId" = l.id
    ), 0) AS on_hand,
    (l."initialQuantity" > 0) OR EXISTS (
      SELECT 1 FROM inventory."Movement" m2
      WHERE m2."lotId" = l.id
        AND m2.type IN ('PRODUZIONE', 'ACQUISTO', 'RIMBORSO_PRODUZIONE', 'RIMBORSO_USO', 'CORRECTION_UP', 'RESO_IN')
    ) AS stockable
  FROM inventory."InventoryLot" l
)
UPDATE inventory."InventoryLot" l
SET status = CASE WHEN s.on_hand > 0 THEN 'OPEN' ELSE 'CLOSED' END::inventory."InventoryLotStatus"
FROM stock s
WHERE s.id = l.id
  AND (
    (s.on_hand > 0 AND l.status IS DISTINCT FROM 'OPEN')
    OR (s.stockable AND s.on_hand <= 0 AND l.status IS DISTINCT FROM 'CLOSED')
  );
