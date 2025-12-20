-- AlterTable
ALTER TABLE "inventory"."Movement" ADD COLUMN     "byUserId" INTEGER;

-- CreateIndex
CREATE INDEX "Movement_byUserId_idx" ON "inventory"."Movement"("byUserId");

-- AddForeignKey
ALTER TABLE "inventory"."Movement" ADD CONSTRAINT "Movement_byUserId_fkey" FOREIGN KEY ("byUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
