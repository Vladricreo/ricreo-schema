-- Costo pagato per lotto d'acquisto dalle fatture di Finance (R-257, 17/11/2026).
-- [utente 17/11: «salvarci anche il prezzo pagato per questo lotto … da considerare cosa e
-- spedizione cosa no dazi costi extra e dividerlo per numeri … costo per lotto fifo»;
-- scelte: ripartizione in proporzione al valore, merce + spedizione + dazi + spese extra − sconti,
-- solo dalla fattura, per ora costo dei lotti + storico]
-- Una riga per lotto con fattura collegata; la calcola Inventory (lib/finance-invoices/lot-costs.ts).

CREATE TABLE IF NOT EXISTS "inventory"."InventoryLotCost" (
  "lotId"           UUID          NOT NULL,
  "quantity"        INTEGER       NOT NULL,
  "goodsCost"       DECIMAL(14,4) NOT NULL,
  "discount"        DECIMAL(14,4) NOT NULL DEFAULT 0,
  "shippingCost"    DECIMAL(14,4) NOT NULL DEFAULT 0,
  "dutyCost"        DECIMAL(14,4) NOT NULL DEFAULT 0,
  "extraCost"       DECIMAL(14,4) NOT NULL DEFAULT 0,
  "totalCost"       DECIMAL(14,4) NOT NULL,
  "unitCost"        DECIMAL(14,6) NOT NULL,
  "currency"        TEXT          NOT NULL DEFAULT 'EUR',
  "basis"           TEXT          NOT NULL,
  "purchaseOrderId" UUID,
  "invoiceNumbers"  TEXT[]        NOT NULL DEFAULT ARRAY[]::TEXT[],
  "detail"          JSONB,
  "computedAt"      TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "InventoryLotCost_pkey" PRIMARY KEY ("lotId"),
  CONSTRAINT "InventoryLotCost_lotId_fkey" FOREIGN KEY ("lotId")
    REFERENCES "inventory"."InventoryLot"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "InventoryLotCost_quantity_check" CHECK ("quantity" > 0),
  CONSTRAINT "InventoryLotCost_basis_check" CHECK ("basis" IN ('righe', 'totale'))
);

CREATE INDEX IF NOT EXISTS "InventoryLotCost_purchaseOrderId_idx"
  ON "inventory"."InventoryLotCost"("purchaseOrderId");

COMMENT ON TABLE "inventory"."InventoryLotCost" IS
  'Costo pagato per lotto d''acquisto dalle fatture di Finance collegate all''ordine (R-257).';

-- Come le altre tabelle inventory: niente accesso da API, le app usano postgres/service_role.
ALTER TABLE "inventory"."InventoryLotCost" ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON "inventory"."InventoryLotCost" FROM anon, authenticated;
