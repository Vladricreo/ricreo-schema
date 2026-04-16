-- CreateTable
CREATE TABLE "inventory"."SupplierDocumentMapping" (
    "id" UUID NOT NULL,
    "supplierId" UUID,
    "supplierNamePattern" TEXT NOT NULL,
    "documentDescription" TEXT NOT NULL,
    "matchedItemId" UUID,
    "matchedProductPartId" UUID,
    "fieldHints" JSONB,
    "timesUsed" INTEGER NOT NULL DEFAULT 1,
    "lastUsedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SupplierDocumentMapping_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "SupplierDocumentMapping_supplierNamePattern_documentDescription_key" ON "inventory"."SupplierDocumentMapping"("supplierNamePattern", "documentDescription");

-- CreateIndex
CREATE INDEX "SupplierDocumentMapping_supplierId_idx" ON "inventory"."SupplierDocumentMapping"("supplierId");

-- AddForeignKey
ALTER TABLE "inventory"."SupplierDocumentMapping" ADD CONSTRAINT "SupplierDocumentMapping_supplierId_fkey" FOREIGN KEY ("supplierId") REFERENCES "inventory"."Supplier"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."SupplierDocumentMapping" ADD CONSTRAINT "SupplierDocumentMapping_matchedItemId_fkey" FOREIGN KEY ("matchedItemId") REFERENCES "inventory"."Item"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."SupplierDocumentMapping" ADD CONSTRAINT "SupplierDocumentMapping_matchedProductPartId_fkey" FOREIGN KEY ("matchedProductPartId") REFERENCES "inventory"."ProductPart"("id") ON DELETE SET NULL ON UPDATE CASCADE;
