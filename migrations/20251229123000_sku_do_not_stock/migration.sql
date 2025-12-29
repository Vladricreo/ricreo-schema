-- AlterTable
ALTER TABLE "inventory"."Sku"
ADD COLUMN     "doNotStock" BOOLEAN NOT NULL DEFAULT false;


