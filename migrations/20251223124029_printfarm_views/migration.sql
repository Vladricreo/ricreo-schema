-- CreateTable
CREATE TABLE "print-farm"."PrinterStateEvent" (
    "id" UUID NOT NULL,
    "number" BIGSERIAL NOT NULL,
    "printerId" UUID NOT NULL,
    "fromOperationalStatus" TEXT,
    "toOperationalStatus" TEXT NOT NULL,
    "fromStatus" TEXT,
    "toStatus" TEXT,
    "source" TEXT NOT NULL DEFAULT 'WSS',
    "at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "metadata" JSONB,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PrinterStateEvent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "print-farm"."PrinterDowntimeEvent" (
    "id" UUID NOT NULL,
    "number" BIGSERIAL NOT NULL,
    "printerId" UUID NOT NULL,
    "category" TEXT NOT NULL DEFAULT 'OTHER',
    "reason" TEXT,
    "severity" TEXT NOT NULL DEFAULT 'WARNING',
    "source" TEXT NOT NULL DEFAULT 'MQTT',
    "openedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "resolvedAt" TIMESTAMPTZ(6),
    "resolvedBy" TEXT,
    "metadata" JSONB,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PrinterDowntimeEvent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "print-farm"."PrintRunMetrics" (
    "id" UUID NOT NULL,
    "printRunId" UUID NOT NULL,
    "filamentUsedGrams" DECIMAL(12,2),
    "wasteGrams" DECIMAL(12,2),
    "notes" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PrintRunMetrics_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "PrinterStateEvent_number_key" ON "print-farm"."PrinterStateEvent"("number");

-- CreateIndex
CREATE INDEX "PrinterStateEvent_printerId_at_idx" ON "print-farm"."PrinterStateEvent"("printerId", "at" DESC);

-- CreateIndex
CREATE INDEX "PrinterStateEvent_toOperationalStatus_at_idx" ON "print-farm"."PrinterStateEvent"("toOperationalStatus", "at" DESC);

-- CreateIndex
CREATE INDEX "PrinterStateEvent_at_idx" ON "print-farm"."PrinterStateEvent"("at" DESC);

-- CreateIndex
CREATE UNIQUE INDEX "PrinterDowntimeEvent_number_key" ON "print-farm"."PrinterDowntimeEvent"("number");

-- CreateIndex
CREATE INDEX "PrinterDowntimeEvent_printerId_openedAt_idx" ON "print-farm"."PrinterDowntimeEvent"("printerId", "openedAt" DESC);

-- CreateIndex
CREATE INDEX "PrinterDowntimeEvent_category_openedAt_idx" ON "print-farm"."PrinterDowntimeEvent"("category", "openedAt" DESC);

-- CreateIndex
CREATE INDEX "PrinterDowntimeEvent_resolvedAt_idx" ON "print-farm"."PrinterDowntimeEvent"("resolvedAt" DESC);

-- CreateIndex
CREATE INDEX "PrinterDowntimeEvent_openedAt_idx" ON "print-farm"."PrinterDowntimeEvent"("openedAt" DESC);

-- CreateIndex
CREATE UNIQUE INDEX "PrintRunMetrics_printRunId_key" ON "print-farm"."PrintRunMetrics"("printRunId");

-- CreateIndex
CREATE INDEX "PrintRunMetrics_printRunId_idx" ON "print-farm"."PrintRunMetrics"("printRunId");

-- AddForeignKey
ALTER TABLE "print-farm"."PrinterStateEvent" ADD CONSTRAINT "PrinterStateEvent_printerId_fkey" FOREIGN KEY ("printerId") REFERENCES "print-farm"."Printer"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."PrinterDowntimeEvent" ADD CONSTRAINT "PrinterDowntimeEvent_printerId_fkey" FOREIGN KEY ("printerId") REFERENCES "print-farm"."Printer"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."PrintRunMetrics" ADD CONSTRAINT "PrintRunMetrics_printRunId_fkey" FOREIGN KEY ("printRunId") REFERENCES "print-farm"."PrintRun"("id") ON DELETE CASCADE ON UPDATE CASCADE;
