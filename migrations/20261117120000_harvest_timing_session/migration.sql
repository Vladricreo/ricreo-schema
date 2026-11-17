-- Tempi di scarico (17/11): un giro del bulk o uno scarico singolo, dall'apertura
-- alla conferma. Tabella nuova, nessun dato esistente toccato. La scrive il client
-- PF dopo la conferma (fail-open: se la tabella manca lo scarico va avanti uguale).

-- CreateTable
CREATE TABLE "print-farm"."HarvestTimingSession" (
    "id" UUID NOT NULL,
    "userId" INTEGER NOT NULL,
    "source" VARCHAR(16) NOT NULL,
    "openedAt" TIMESTAMPTZ(6) NOT NULL,
    "submittedAt" TIMESTAMPTZ(6) NOT NULL,
    "hiddenMs" INTEGER NOT NULL DEFAULT 0,
    "harvestIds" UUID[],
    "printerCount" INTEGER NOT NULL DEFAULT 0,
    "partsTotal" INTEGER NOT NULL DEFAULT 0,
    "partsRejected" INTEGER NOT NULL DEFAULT 0,
    "aisleCodes" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "clockSkewMs" INTEGER,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "HarvestTimingSession_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "HarvestTimingSession_submittedAt_idx" ON "print-farm"."HarvestTimingSession"("submittedAt");

-- CreateIndex
CREATE INDEX "HarvestTimingSession_userId_submittedAt_idx" ON "print-farm"."HarvestTimingSession"("userId", "submittedAt");

-- Letta e scritta via Prisma (bypassa RLS): RLS senza policy chiude l'accesso anon.
ALTER TABLE "print-farm"."HarvestTimingSession" ENABLE ROW LEVEL SECURITY;
