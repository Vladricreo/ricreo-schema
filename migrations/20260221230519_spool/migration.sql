-- AlterTable
ALTER TABLE "print-farm"."PrintRun" ADD COLUMN     "completionPercent" SMALLINT;

-- AlterTable
ALTER TABLE "print-farm"."PrintRunMetrics" ADD COLUMN     "expectedFilamentGrams" DECIMAL(12,2),
ADD COLUMN     "lastSnapshotAt" TIMESTAMPTZ(6),
ADD COLUMN     "lastSnapshotGrams" DECIMAL(12,2),
ADD COLUMN     "lastSnapshotPercent" SMALLINT;
