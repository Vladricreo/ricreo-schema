-- AlterTable
ALTER TABLE "print-farm"."ProjectThreeMFFile" ADD COLUMN     "objectCount" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "printerModelId" TEXT,
ADD COLUMN     "sliceFilaments" JSONB,
ADD COLUMN     "supportsUsed" BOOLEAN NOT NULL DEFAULT false;
