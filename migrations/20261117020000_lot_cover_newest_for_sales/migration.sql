-- Spedizioni: il lotto più nuovo esce prima (R-249, 16/11/2026).
-- [utente 16/11: «le spedizioni, bisogna collegarle con il lotto, usiamo per ora Fifo
-- al contrario, cioe il piu nuovo viene spedito prima, poi metteremo il barcode che
-- scansioneremo ogni prodotto prima di spedirlo»]
-- La copertura automatica (R-247) di una VENDITA di prodotto finito prende il
-- mancante dai lotti aperti più NUOVI, come la scelta del lotto in spedizione;
-- per tutte le altre uscite resta dai più vecchi (FIFO).

CREATE OR REPLACE FUNCTION "inventory".cover_negative_lot()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_lot inventory."InventoryLot"%ROWTYPE;
  v_deficit INT;
  v_take INT;
  v_avail INT;
  d RECORD;
BEGIN
  IF NEW."lotId" IS NULL OR NEW.type NOT IN ('USO','TRASH','VENDITA','CORRECTION_DOWN') THEN
    RETURN NEW;
  END IF;

  v_deficit := -inventory.lot_stockable_quantity(NEW."lotId");
  IF v_deficit > 0 THEN
    SELECT * INTO v_lot FROM inventory."InventoryLot" WHERE id = NEW."lotId";

    FOR d IN
      SELECT o.id
        FROM inventory."InventoryLot" o
       WHERE o.id <> v_lot.id
         AND o.status = 'OPEN'
         AND CASE
               WHEN v_lot."productPartId" IS NOT NULL THEN o."productPartId" = v_lot."productPartId"
               WHEN v_lot."productId" IS NOT NULL THEN o."productId" = v_lot."productId" AND o."productPartId" IS NULL
               WHEN v_lot."itemId" IS NOT NULL THEN o."itemId" = v_lot."itemId"
               ELSE FALSE
             END
       ORDER BY
         CASE WHEN NEW.type = 'VENDITA' AND v_lot."productPartId" IS NULL AND v_lot."productId" IS NOT NULL
              THEN COALESCE(o."receivedAt", o."manufacturedAt", o."createdAt") END DESC,
         CASE WHEN NEW.type = 'VENDITA' AND v_lot."productPartId" IS NULL AND v_lot."productId" IS NOT NULL
              THEN o."createdAt" END DESC,
         COALESCE(o."receivedAt", o."manufacturedAt", o."createdAt"), o."createdAt"
       FOR UPDATE
    LOOP
      EXIT WHEN v_deficit <= 0;
      v_avail := inventory.lot_stockable_quantity(d.id);
      CONTINUE WHEN v_avail <= 0;
      v_take := LEAST(v_avail, v_deficit);
      INSERT INTO inventory."InventoryLotAdjustment" ("lotId", quantity, reason, "movementId", "batchId", note, "byUserId")
      VALUES
        (d.id, -v_take, 'AUTO_COVER', NEW.id, NEW.id,
         format('Pezzi spostati sul lotto %s: l''uscita %s ne superava il residuo', v_lot.code, NEW.type), NEW."byUserId"),
        (v_lot.id, v_take, 'AUTO_COVER', NEW.id, NEW.id,
         format('Copertura automatica di un''uscita %s oltre il residuo del lotto', NEW.type), NEW."byUserId");
      v_deficit := v_deficit - v_take;
    END LOOP;
  END IF;

  -- Lo stato del lotto tiene conto delle rettifiche (il trigger storico no).
  PERFORM inventory.refresh_lot_status(NEW."lotId");
  RETURN NEW;
END;
$$;
