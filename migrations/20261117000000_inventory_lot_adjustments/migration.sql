-- Riallineamento dei lotti (R-247, 16/11/2026).
--
-- Problema: le uscite finivano su lotti già vuoti (lotti in negativo) mentre i
-- lotti vecchi restavano aperti con pezzi che non esistono più. Cause: il FIFO del
-- codice calcolava il residuo diversamente dalla vista; molti flussi mettono tutta
-- l'uscita su un solo lotto; le correzioni d'ingresso aprivano lotti nuovi.
--
-- Soluzione [utente 16/11: «Riallineamento tracciato», «correzione d'ingresso nel
-- lotto aperto più recente»]:
-- 1) `InventoryLotAdjustment`: rettifiche di SOLO lotto (non toccano giacenze né
--    movimenti). La vista del residuo e lo stato aperto/chiuso le sommano.
-- 2) `inventory.lot_stockable_quantity(lot)`: un solo calcolo del residuo «a
--    magazzino» (senza WIP di fase), usato da vista, trigger e codice FIFO.
-- 3) Protezione: quando un'uscita manda un lotto sotto zero, un trigger sposta il
--    mancante dai lotti aperti più vecchi della stessa entità (coppie di
--    rettifiche AUTO_COVER legate al movimento; spariscono se il movimento si annulla).
-- 4) Riallineamento del passato (REALIGN): per ogni articolo, parte e prodotto la
--    giacenza reale va prima ai lotti presenti nelle odette, poi ai lotti più
--    recenti fino ai pezzi entrati; gli altri lotti si chiudono.

-- ---------------------------------------------------------------------------
-- 1) Tabella
-- ---------------------------------------------------------------------------
CREATE TYPE "inventory"."LotAdjustmentReason" AS ENUM ('REALIGN', 'AUTO_COVER');

CREATE TABLE "inventory"."InventoryLotAdjustment" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "lotId" UUID NOT NULL,
    "quantity" INTEGER NOT NULL,
    "reason" "inventory"."LotAdjustmentReason" NOT NULL,
    "movementId" UUID,
    "batchId" UUID,
    "note" TEXT,
    "byUserId" INTEGER,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "InventoryLotAdjustment_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "InventoryLotAdjustment_quantity_check" CHECK ("quantity" <> 0)
);

CREATE INDEX "InventoryLotAdjustment_lotId_idx" ON "inventory"."InventoryLotAdjustment"("lotId");
CREATE INDEX "InventoryLotAdjustment_movementId_idx" ON "inventory"."InventoryLotAdjustment"("movementId");
CREATE INDEX "InventoryLotAdjustment_batchId_idx" ON "inventory"."InventoryLotAdjustment"("batchId");

ALTER TABLE "inventory"."InventoryLotAdjustment" ADD CONSTRAINT "InventoryLotAdjustment_lotId_fkey" FOREIGN KEY ("lotId") REFERENCES "inventory"."InventoryLot"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "inventory"."InventoryLotAdjustment" ADD CONSTRAINT "InventoryLotAdjustment_movementId_fkey" FOREIGN KEY ("movementId") REFERENCES "inventory"."Movement"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "inventory"."InventoryLotAdjustment" ADD CONSTRAINT "InventoryLotAdjustment_byUserId_fkey" FOREIGN KEY ("byUserId") REFERENCES "public"."User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- Come le altre tabelle inventory: RLS attiva, nessun accesso dalle chiavi pubbliche.
ALTER TABLE "inventory"."InventoryLotAdjustment" ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON "inventory"."InventoryLotAdjustment" FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2) Residuo «a magazzino» (SSOT) e stato del lotto
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "inventory".lot_stockable_quantity(p_lot UUID)
RETURNS INTEGER
LANGUAGE sql
STABLE
AS $$
  SELECT (
    (CASE WHEN EXISTS (
       SELECT 1 FROM inventory."Movement" mi
        WHERE mi."lotId" = p_lot
          AND mi.type IN ('PRODUZIONE','ACQUISTO','RIMBORSO_PRODUZIONE','RIMBORSO_USO','CORRECTION_UP','RESO_IN')
     ) THEN 0 ELSE COALESCE((SELECT l."initialQuantity" FROM inventory."InventoryLot" l WHERE l.id = p_lot), 0) END)
    + COALESCE((
        SELECT SUM(CASE
          WHEN m.type IN ('PRODUZIONE','ACQUISTO','RIMBORSO_PRODUZIONE','RIMBORSO_USO','CORRECTION_UP','RESO_IN') THEN m.quantity
          WHEN m.type IN ('USO','TRASH','VENDITA','CORRECTION_DOWN') THEN -m.quantity
          ELSE 0 END)
        FROM inventory."Movement" m WHERE m."lotId" = p_lot), 0)
    + COALESCE((SELECT SUM(a.quantity) FROM inventory."InventoryLotAdjustment" a WHERE a."lotId" = p_lot), 0)
  )::int;
$$;

CREATE OR REPLACE FUNCTION "inventory".refresh_lot_status(p_lot UUID)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  v_stock INT;
  v_stockable BOOLEAN;
BEGIN
  IF p_lot IS NULL THEN RETURN; END IF;
  v_stock := inventory.lot_stockable_quantity(p_lot);
  SELECT (l."initialQuantity" > 0)
      OR EXISTS (SELECT 1 FROM inventory."Movement" m
                  WHERE m."lotId" = p_lot
                    AND m.type IN ('PRODUZIONE','ACQUISTO','RIMBORSO_PRODUZIONE','RIMBORSO_USO','CORRECTION_UP','RESO_IN'))
      OR EXISTS (SELECT 1 FROM inventory."InventoryLotAdjustment" a WHERE a."lotId" = p_lot)
    INTO v_stockable
    FROM inventory."InventoryLot" l WHERE l.id = p_lot;

  IF COALESCE(v_stockable, FALSE) AND v_stock <= 0 THEN
    UPDATE inventory."InventoryLot" SET status = 'CLOSED', "updatedAt" = NOW()
     WHERE id = p_lot AND status IS DISTINCT FROM 'CLOSED';
  ELSIF v_stock > 0 THEN
    UPDATE inventory."InventoryLot" SET status = 'OPEN', "updatedAt" = NOW()
     WHERE id = p_lot AND status IS DISTINCT FROM 'OPEN';
  END IF;
END;
$$;

-- Vista: stessi campi; il residuo somma anche le rettifiche di lotto.
CREATE OR REPLACE VIEW "inventory_views"."v_inventory_lot_remaining" AS
SELECT l.id AS lot_id,
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
    COALESCE((SELECT sum(m.quantity) FROM inventory."Movement" m
               WHERE m."lotId" = l.id
                 AND m.type IN ('PRODUZIONE','ACQUISTO','RIMBORSO_PRODUZIONE','RIMBORSO_USO','CORRECTION_UP','STAGE_IN','RESO_IN')), 0::bigint)::integer AS total_in,
    COALESCE((SELECT sum(m.quantity) FROM inventory."Movement" m
               WHERE m."lotId" = l.id
                 AND m.type IN ('USO','TRASH','VENDITA','CORRECTION_DOWN','STAGE_OUT')), 0::bigint)::integer AS total_out,
    (
      CASE WHEN EXISTS (SELECT 1 FROM inventory."Movement" mi
                         WHERE mi."lotId" = l.id
                           AND mi.type IN ('PRODUZIONE','ACQUISTO','RIMBORSO_PRODUZIONE','RIMBORSO_USO','CORRECTION_UP','RESO_IN'))
           THEN 0 ELSE l."initialQuantity" END
      + COALESCE((SELECT sum(CASE
            WHEN m.type IN ('PRODUZIONE','ACQUISTO','RIMBORSO_PRODUZIONE','RIMBORSO_USO','CORRECTION_UP','STAGE_IN','RESO_IN') THEN m.quantity
            WHEN m.type IN ('USO','TRASH','VENDITA','CORRECTION_DOWN','STAGE_OUT') THEN -m.quantity
            ELSE 0 END)
          FROM inventory."Movement" m WHERE m."lotId" = l.id), 0::bigint)
      + COALESCE((SELECT sum(a.quantity) FROM inventory."InventoryLotAdjustment" a WHERE a."lotId" = l.id), 0::bigint)
    )::integer AS remaining_quantity
FROM inventory."InventoryLot" l;

-- ---------------------------------------------------------------------------
-- 3) Protezione: copertura automatica di un lotto mandato sotto zero
-- ---------------------------------------------------------------------------
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
       ORDER BY COALESCE(o."receivedAt", o."manufacturedAt", o."createdAt"), o."createdAt"
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

-- Nome dopo `after_movement_insert`: gira dopo l'aggiornamento delle giacenze.
CREATE TRIGGER after_movement_lot_cover
AFTER INSERT ON "inventory"."Movement"
FOR EACH ROW EXECUTE FUNCTION "inventory".cover_negative_lot();

CREATE OR REPLACE FUNCTION "inventory".refresh_lot_status_on_movement_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM inventory.refresh_lot_status(OLD."lotId");
  RETURN OLD;
END;
$$;

CREATE TRIGGER after_movement_lot_status_refresh
AFTER DELETE ON "inventory"."Movement"
FOR EACH ROW EXECUTE FUNCTION "inventory".refresh_lot_status_on_movement_delete();

CREATE OR REPLACE FUNCTION "inventory".refresh_lot_status_on_adjustment()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM inventory.refresh_lot_status(OLD."lotId");
    RETURN OLD;
  END IF;
  PERFORM inventory.refresh_lot_status(NEW."lotId");
  RETURN NEW;
END;
$$;

CREATE TRIGGER after_lot_adjustment_change
AFTER INSERT OR DELETE ON "inventory"."InventoryLotAdjustment"
FOR EACH ROW EXECUTE FUNCTION "inventory".refresh_lot_status_on_adjustment();

-- ---------------------------------------------------------------------------
-- 4) Riallineamento del passato
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_batch UUID := gen_random_uuid();
  e RECORD;
  l RECORD;
  v_left INT;
  v_give INT;
BEGIN
  CREATE TEMP TABLE realign_lot ON COMMIT DROP AS
  SELECT lt.id,
         CASE WHEN lt."productPartId" IS NOT NULL THEN 'PART'
              WHEN lt."productId" IS NOT NULL THEN 'SKU'
              WHEN lt."itemId" IS NOT NULL THEN 'ITEM' END AS kind,
         COALESCE(lt."productPartId", lt."productId", lt."itemId") AS eid,
         COALESCE(lt."receivedAt", lt."manufacturedAt", lt."createdAt") AS ingress,
         lt."createdAt",
         inventory.lot_stockable_quantity(lt.id) AS stockable,
         (CASE WHEN EXISTS (SELECT 1 FROM inventory."Movement" mi WHERE mi."lotId" = lt.id
                 AND mi.type IN ('PRODUZIONE','ACQUISTO','RIMBORSO_PRODUZIONE','RIMBORSO_USO','CORRECTION_UP','RESO_IN'))
               THEN 0 ELSE lt."initialQuantity" END
          + COALESCE((SELECT SUM(m.quantity) FROM inventory."Movement" m WHERE m."lotId" = lt.id
                 AND m.type IN ('PRODUZIONE','ACQUISTO','RIMBORSO_PRODUZIONE','RIMBORSO_USO','CORRECTION_UP','RESO_IN')), 0))::int AS capacity,
         COALESCE((SELECT SUM(oc.quantity) FROM inventory."OdetteContent" oc
                    WHERE oc."inventoryLotId" = lt.id AND oc.quantity > 0), 0)::int AS in_odette,
         0 AS target
    FROM inventory."InventoryLot" lt;

  DELETE FROM realign_lot WHERE kind IS NULL;
  CREATE INDEX ON realign_lot (kind, eid);

  CREATE TEMP TABLE realign_stock ON COMMIT DROP AS
  SELECT 'ITEM'::text AS kind, v."itemId" AS eid, GREATEST(v.calculated_stock, 0)::int AS s
    FROM inventory_views.v_item_stock v
  UNION ALL
  SELECT 'PART', v."productPartId", GREATEST(v.calculated_stock, 0)::int
    FROM inventory_views.v_product_part_stock v
  UNION ALL
  SELECT 'SKU', sk."productId", GREATEST(SUM(COALESCE(v.calculated_stock, 0)), 0)::int
    FROM inventory."Sku" sk
    LEFT JOIN inventory_views.v_sku_stock v ON v."skuId" = sk.id
   GROUP BY sk."productId";

  FOR e IN SELECT DISTINCT r.kind, r.eid, COALESCE(s.s, 0) AS s
             FROM realign_lot r
             LEFT JOIN realign_stock s ON s.kind = r.kind AND s.eid = r.eid
  LOOP
    v_left := e.s;

    -- a) i lotti che stanno davvero in un'odetta (più recenti prima)
    FOR l IN SELECT id, in_odette FROM realign_lot
              WHERE kind = e.kind AND eid = e.eid AND in_odette > 0
              ORDER BY ingress DESC, "createdAt" DESC
    LOOP
      EXIT WHEN v_left <= 0;
      v_give := LEAST(l.in_odette, v_left);
      UPDATE realign_lot SET target = target + v_give WHERE id = l.id;
      v_left := v_left - v_give;
    END LOOP;

    -- b) il resto ai lotti più recenti, fino ai pezzi entrati
    FOR l IN SELECT id, capacity, target FROM realign_lot
              WHERE kind = e.kind AND eid = e.eid
              ORDER BY ingress DESC, "createdAt" DESC
    LOOP
      EXIT WHEN v_left <= 0;
      v_give := LEAST(GREATEST(l.capacity - l.target, 0), v_left);
      IF v_give > 0 THEN
        UPDATE realign_lot SET target = target + v_give WHERE id = l.id;
        v_left := v_left - v_give;
      END IF;
    END LOOP;

    -- c) giacenza oltre i pezzi entrati nei lotti: sul lotto più recente
    IF v_left > 0 THEN
      UPDATE realign_lot SET target = target + v_left
       WHERE id = (SELECT id FROM realign_lot WHERE kind = e.kind AND eid = e.eid
                    ORDER BY ingress DESC, "createdAt" DESC LIMIT 1);
    END IF;
  END LOOP;

  INSERT INTO inventory."InventoryLotAdjustment" ("lotId", quantity, reason, "batchId", note)
  SELECT r.id, r.target - r.stockable, 'REALIGN', v_batch,
         format('Riallineamento del 16/11/2026: residuo da %s a %s per allinearlo alla giacenza reale (pezzi nelle odette, poi lotti più recenti). Giacenze invariate.',
                r.stockable, r.target)
    FROM realign_lot r
   WHERE r.target <> r.stockable;
END;
$$;

-- Stato di tutti i lotti ricalcolato con la nuova regola (anche quelli non toccati,
-- per allinearli al residuo con le rettifiche).
SELECT inventory.refresh_lot_status(id) FROM inventory."InventoryLot";
