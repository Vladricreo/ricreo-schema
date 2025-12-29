/*
  Warnings:

  - You are about to drop the column `sliceFilaments` on the `ProjectThreeMFFile` table. All the data in the column will be lost.

*/
-- AlterTable
ALTER TABLE "print-farm"."ProjectThreeMFFile" DROP COLUMN "sliceFilaments",
ADD COLUMN     "sliceObjects" JSONB;
