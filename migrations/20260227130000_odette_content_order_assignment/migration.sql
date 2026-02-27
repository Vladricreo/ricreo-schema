-- Aggiunge collegamenti a ProductOrder e PrinterAssignment per OdetteContent.
-- Scopo: evitare creazione righe duplicate per ogni scarico e migliorare tracciabilità.

-- AlterTable
ALTER TABLE "inventory"."OdetteContent"
  ADD COLUMN "productOrderId" uuid,
  ADD COLUMN "assignmentId" uuid;

-- CreateIndex
CREATE INDEX "OdetteContent_productOrderId_idx" ON "inventory"."OdetteContent"("productOrderId");
CREATE INDEX "OdetteContent_assignmentId_idx" ON "inventory"."OdetteContent"("assignmentId");

-- AddForeignKey
ALTER TABLE "inventory"."OdetteContent"
  ADD CONSTRAINT "OdetteContent_productOrderId_fkey"
  FOREIGN KEY ("productOrderId")
  REFERENCES "inventory"."ProductOrder"("id")
  ON DELETE SET NULL
  ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."OdetteContent"
  ADD CONSTRAINT "OdetteContent_assignmentId_fkey"
  FOREIGN KEY ("assignmentId")
  REFERENCES "print-farm"."PrinterAssignment"("id")
  ON DELETE SET NULL
  ON UPDATE CASCADE;

