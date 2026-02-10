-- CreateTable
CREATE TABLE "print-farm"."SpoolInventory" (
    "id" UUID NOT NULL,
    "materialCategory" TEXT NOT NULL,
    "colorHex" TEXT,
    "quantity" INTEGER NOT NULL DEFAULT 0,
    "notes" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SpoolInventory_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "SpoolInventory_materialCategory_colorHex_key" ON "print-farm"."SpoolInventory"("materialCategory", "colorHex");
