-- AlterTable: aggiunge colonna locationId a SpoolTag
ALTER TABLE "print-farm"."SpoolTag" ADD COLUMN IF NOT EXISTS "locationId" UUID;

-- CreateIndex
CREATE INDEX IF NOT EXISTS "SpoolTag_locationId_idx" ON "print-farm"."SpoolTag"("locationId");

-- AddForeignKey: SpoolTag → WarehouseLocation
DO $$ BEGIN
  ALTER TABLE "print-farm"."SpoolTag"
      ADD CONSTRAINT "SpoolTag_locationId_fkey"
      FOREIGN KEY ("locationId")
      REFERENCES "inventory"."WarehouseLocation"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
