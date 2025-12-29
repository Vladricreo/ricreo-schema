-- DropForeignKey
ALTER TABLE "print-farm"."PrintRun" DROP CONSTRAINT "PrintRun_fileId_fkey";

-- AddForeignKey
ALTER TABLE "print-farm"."PrintRun" ADD CONSTRAINT "PrintRun_fileId_fkey" FOREIGN KEY ("fileId") REFERENCES "print-farm"."ProjectThreeMFFile"("id") ON DELETE SET NULL ON UPDATE CASCADE;
