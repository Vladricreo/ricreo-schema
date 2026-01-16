-- CreateEnum
CREATE TYPE "print-farm"."QueueTaskStatus" AS ENUM ('PENDING', 'CHECKING', 'UPLOADING', 'PROCESSING', 'QUEUING', 'COMPLETED', 'SKIPPED', 'ERROR', 'CANCELLED');

-- CreateTable
CREATE TABLE "print-farm"."QueueTask" (
    "id" UUID NOT NULL,
    "batchId" UUID NOT NULL,
    "printerId" UUID NOT NULL,
    "printerName" VARCHAR(255) NOT NULL,
    "printerSerial" VARCHAR(255),
    "assignmentId" UUID,
    "productionJobId" UUID,
    "fileId" UUID,
    "status" "print-farm"."QueueTaskStatus" NOT NULL DEFAULT 'PENDING',
    "uploadProgress" INTEGER,
    "uploadId" VARCHAR(255),
    "filePresence" VARCHAR(50) DEFAULT 'unknown',
    "foundFilename" VARCHAR(255),
    "jobName" VARCHAR(255),
    "fileName" VARCHAR(255),
    "thumbnailUrl" TEXT,
    "currentMaterial" VARCHAR(100),
    "currentColor" VARCHAR(100),
    "requiredMaterial" VARCHAR(100),
    "requiredColor" VARCHAR(100),
    "requiredMaterials" JSONB,
    "amsSlots" JSONB,
    "queuePosition" INTEGER,
    "printRunId" UUID,
    "error" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "startedAt" TIMESTAMPTZ(6),
    "completedAt" TIMESTAMPTZ(6),
    "expiresAt" TIMESTAMPTZ(6),

    CONSTRAINT "QueueTask_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "QueueTask_printRunId_key" ON "print-farm"."QueueTask"("printRunId");

-- CreateIndex
CREATE INDEX "QueueTask_batchId_idx" ON "print-farm"."QueueTask"("batchId");

-- CreateIndex
CREATE INDEX "QueueTask_printerId_idx" ON "print-farm"."QueueTask"("printerId");

-- CreateIndex
CREATE INDEX "QueueTask_status_idx" ON "print-farm"."QueueTask"("status");

-- CreateIndex
CREATE INDEX "QueueTask_createdAt_idx" ON "print-farm"."QueueTask"("createdAt" DESC);

-- CreateIndex
CREATE INDEX "QueueTask_expiresAt_idx" ON "print-farm"."QueueTask"("expiresAt");

-- AddForeignKey
ALTER TABLE "print-farm"."QueueTask" ADD CONSTRAINT "QueueTask_printerId_fkey" FOREIGN KEY ("printerId") REFERENCES "print-farm"."Printer"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."QueueTask" ADD CONSTRAINT "QueueTask_assignmentId_fkey" FOREIGN KEY ("assignmentId") REFERENCES "print-farm"."PrinterAssignment"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."QueueTask" ADD CONSTRAINT "QueueTask_productionJobId_fkey" FOREIGN KEY ("productionJobId") REFERENCES "print-farm"."ProductionJob"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."QueueTask" ADD CONSTRAINT "QueueTask_fileId_fkey" FOREIGN KEY ("fileId") REFERENCES "print-farm"."ProjectThreeMFFile"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."QueueTask" ADD CONSTRAINT "QueueTask_printRunId_fkey" FOREIGN KEY ("printRunId") REFERENCES "print-farm"."PrintRun"("id") ON DELETE SET NULL ON UPDATE CASCADE;
