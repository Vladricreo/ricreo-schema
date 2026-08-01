-- ============================================================================
-- SCHEDULER F2 — SCADENZE ORDINI
-- ============================================================================

ALTER TABLE "inventory"."ProductOrder"
  ADD COLUMN "dueDate" TIMESTAMPTZ(6);

CREATE INDEX "ProductOrder_dueDate_idx"
  ON "inventory"."ProductOrder"("dueDate");
