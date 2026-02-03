/*
  Warnings:

  - You are about to drop the `OdetteAssemblyAssignment` table. If the table is not empty, all the data it contains will be lost.

*/
-- DropForeignKey
ALTER TABLE "inventory"."OdetteAssemblyAssignment" DROP CONSTRAINT "OdetteAssemblyAssignment_assemblyOrderId_fkey";

-- DropForeignKey
ALTER TABLE "inventory"."OdetteAssemblyAssignment" DROP CONSTRAINT "OdetteAssemblyAssignment_odetteId_fkey";

-- AlterTable
ALTER TABLE "inventory"."OdetteContent" ADD COLUMN     "assemblyOrderId" UUID;

-- DropTable
DROP TABLE "inventory"."OdetteAssemblyAssignment";

-- DropEnum
DROP TYPE "inventory"."OdetteAssignmentRole";

-- CreateIndex
CREATE INDEX "OdetteContent_assemblyOrderId_idx" ON "inventory"."OdetteContent"("assemblyOrderId");

-- CreateIndex
CREATE INDEX "OdetteContent_odetteId_skuId_assemblyStageId_assemblyOrderI_idx" ON "inventory"."OdetteContent"("odetteId", "skuId", "assemblyStageId", "assemblyOrderId");

-- AddForeignKey
ALTER TABLE "inventory"."OdetteContent" ADD CONSTRAINT "OdetteContent_assemblyOrderId_fkey" FOREIGN KEY ("assemblyOrderId") REFERENCES "inventory"."AssemblyOrder"("id") ON DELETE SET NULL ON UPDATE CASCADE;
