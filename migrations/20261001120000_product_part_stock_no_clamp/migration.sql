-- ProductPart.inStock senza limite a 0 nel trigger.
--
-- Con GREATEST(0, ...) un'uscita oltre la giacenza in cache veniva troncata e il
-- rientro successivo (es. STAGE_IN di uno spostamento tra odette, annullamento
-- di un movimento) gonfiava `inStock` rispetto alla somma dei movimenti. Lato
-- assemblaggio la differenza compariva come parti "loose" inesistenti
-- (loose = inStock - quantità in odette).
--
-- Ora `ProductPart.inStock` segue esattamente `v_product_part_stock`, come già fa
-- `reconcile_all_stock()`. Item, AssemblyStage e Sku restano invariati.
-- Riferimento: prisma/custom_migrations/sql/stock_views_and_triggers.sql (sezione 3).

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
  IF NEW."skuId" IS NOT NULL THEN
    -- Per coerenza con v_sku_stock: i movimenti STAGE_IN/STAGE_OUT (WIP) non devono impattare lo stock SKU,
    -- anche se hanno skuId valorizzato.
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
