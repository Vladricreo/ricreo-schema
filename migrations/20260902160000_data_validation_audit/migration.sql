-- Audit e snapshot per la pagina Validazione Dati (igiene F0).

CREATE TABLE IF NOT EXISTS "print-farm"."DataValidationFixLog" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "checkId" TEXT NOT NULL,
    "action" TEXT NOT NULL,
    "targetIds" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    "affected" INTEGER NOT NULL DEFAULT 0,
    "dryRun" BOOLEAN NOT NULL DEFAULT false,
    "performedBy" TEXT NOT NULL,
    "metadata" JSONB,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT now(),

    CONSTRAINT "DataValidationFixLog_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "DataValidationFixLog_checkId_createdAt_idx"
    ON "print-farm"."DataValidationFixLog"("checkId", "createdAt");

CREATE INDEX IF NOT EXISTS "DataValidationFixLog_createdAt_idx"
    ON "print-farm"."DataValidationFixLog"("createdAt");

CREATE TABLE IF NOT EXISTS "print-farm"."DataValidationSnapshot" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "capturedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT now(),
    "windowDays" INTEGER,
    "checkId" TEXT NOT NULL,
    "family" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "count" INTEGER NOT NULL,
    "sampleSize" INTEGER,
    "severity" TEXT NOT NULL,

    CONSTRAINT "DataValidationSnapshot_pkey" PRIMARY KEY ("id")
);

CREATE INDEX IF NOT EXISTS "DataValidationSnapshot_capturedAt_idx"
    ON "print-farm"."DataValidationSnapshot"("capturedAt");

CREATE INDEX IF NOT EXISTS "DataValidationSnapshot_checkId_capturedAt_idx"
    ON "print-farm"."DataValidationSnapshot"("checkId", "capturedAt");
