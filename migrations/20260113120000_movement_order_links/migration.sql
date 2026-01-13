-- Add per-task audit links to Movement
-- - assemblyOrderId: inventory.AssemblyOrder (audit per ordine di assemblaggio)
-- - productOrderId:  inventory.ProductOrder (audit per ordine di produzione, futuro)

-- AlterTable
ALTER TABLE "inventory"."Movement"
ADD COLUMN     "assemblyOrderId" UUID,
ADD COLUMN     "productOrderId" UUID;

-- Indexes (performance for per-order stage progress queries)
CREATE INDEX "Movement_assemblyOrderId_idx" ON "inventory"."Movement"("assemblyOrderId");
CREATE INDEX "Movement_productOrderId_idx" ON "inventory"."Movement"("productOrderId");
CREATE INDEX "Movement_assemblyOrderId_assemblyStageId_type_idx"
ON "inventory"."Movement"("assemblyOrderId", "assemblyStageId", "type");
CREATE INDEX "Movement_assemblyOrderId_date_idx"
ON "inventory"."Movement"("assemblyOrderId", "date" DESC);

-- Foreign Keys
ALTER TABLE "inventory"."Movement"
ADD CONSTRAINT "Movement_assemblyOrderId_fkey"
FOREIGN KEY ("assemblyOrderId") REFERENCES "inventory"."AssemblyOrder"("id")
ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "inventory"."Movement"
ADD CONSTRAINT "Movement_productOrderId_fkey"
FOREIGN KEY ("productOrderId") REFERENCES "inventory"."ProductOrder"("id")
ON DELETE SET NULL ON UPDATE CASCADE;

