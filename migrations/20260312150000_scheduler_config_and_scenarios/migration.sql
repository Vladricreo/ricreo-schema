-- Scheduler Config Profiles & Scenario Analysis
-- Tabelle dedicate per configurazione versionata dello scheduler e analisi scenari.

-- ============================================================================
-- ENUMS
-- ============================================================================

-- Stato profilo configurazione scheduler
CREATE TYPE "print-farm"."SchedulerConfigProfileStatus" AS ENUM ('DRAFT', 'ACTIVE', 'ARCHIVED');

-- Tipo di run scenario (reale o simulazione)
CREATE TYPE "print-farm"."SchedulerRunType" AS ENUM ('REAL', 'SIMULATION');

-- ============================================================================
-- TABLES
-- ============================================================================

-- Profilo di configurazione scheduler: set versionato di pesi, penalità e flag.
CREATE TABLE "print-farm"."SchedulerConfigProfile" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "name" TEXT NOT NULL,
    "status" "print-farm"."SchedulerConfigProfileStatus" NOT NULL DEFAULT 'DRAFT',
    "notes" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SchedulerConfigProfile_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "SchedulerConfigProfile_status_idx" ON "print-farm"."SchedulerConfigProfile"("status");

-- Singolo parametro chiave/valore di un profilo di configurazione.
CREATE TABLE "print-farm"."SchedulerConfigValue" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "profileId" UUID NOT NULL,
    "key" TEXT NOT NULL,
    "valueNum" DECIMAL(16,4),
    "valueBool" BOOLEAN,
    "valueText" TEXT,
    "category" TEXT NOT NULL DEFAULT 'general',
    "description" TEXT,
    "editable" BOOLEAN NOT NULL DEFAULT true,

    CONSTRAINT "SchedulerConfigValue_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "SchedulerConfigValue_profileId_key_key" ON "print-farm"."SchedulerConfigValue"("profileId", "key");
CREATE INDEX "SchedulerConfigValue_profileId_idx" ON "print-farm"."SchedulerConfigValue"("profileId");

-- Esecuzione (reale o simulata) dello scheduler con uno specifico profilo.
CREATE TABLE "print-farm"."SchedulerScenarioRun" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "profileId" UUID,
    "runType" "print-farm"."SchedulerRunType" NOT NULL DEFAULT 'REAL',
    "label" TEXT,
    "configSnapshot" JSONB,
    "solverStatus" TEXT,
    "solverObjective" DECIMAL(16,2),
    "solverDurationMs" INTEGER,
    "jobsEvaluated" INTEGER NOT NULL DEFAULT 0,
    "printersEvaluated" INTEGER NOT NULL DEFAULT 0,
    "assignmentsCreated" INTEGER NOT NULL DEFAULT 0,
    "assignmentsKept" INTEGER NOT NULL DEFAULT 0,
    "inputMetadata" JSONB,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SchedulerScenarioRun_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "SchedulerScenarioRun_runType_idx" ON "print-farm"."SchedulerScenarioRun"("runType");
CREATE INDEX "SchedulerScenarioRun_createdAt_idx" ON "print-farm"."SchedulerScenarioRun"("createdAt");

-- Matrice candidato job-printer di uno scenario.
CREATE TABLE "print-farm"."SchedulerScenarioCandidate" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "runId" UUID NOT NULL,
    "jobId" UUID NOT NULL,
    "jobNumber" TEXT,
    "printerId" UUID NOT NULL,
    "printerName" TEXT,
    "feasible" BOOLEAN NOT NULL DEFAULT true,
    "hardFailReason" TEXT,
    "score" INTEGER NOT NULL DEFAULT 0,
    "penalty" INTEGER NOT NULL DEFAULT 0,
    "net" INTEGER NOT NULL DEFAULT 0,
    "selected" BOOLEAN NOT NULL DEFAULT false,
    "breakdown" JSONB,

    CONSTRAINT "SchedulerScenarioCandidate_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "SchedulerScenarioCandidate_runId_idx" ON "print-farm"."SchedulerScenarioCandidate"("runId");
CREATE INDEX "SchedulerScenarioCandidate_runId_jobId_idx" ON "print-farm"."SchedulerScenarioCandidate"("runId", "jobId");
CREATE INDEX "SchedulerScenarioCandidate_runId_printerId_idx" ON "print-farm"."SchedulerScenarioCandidate"("runId", "printerId");

-- ============================================================================
-- FOREIGN KEYS
-- ============================================================================

ALTER TABLE "print-farm"."SchedulerConfigValue"
    ADD CONSTRAINT "SchedulerConfigValue_profileId_fkey"
    FOREIGN KEY ("profileId") REFERENCES "print-farm"."SchedulerConfigProfile"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "print-farm"."SchedulerScenarioRun"
    ADD CONSTRAINT "SchedulerScenarioRun_profileId_fkey"
    FOREIGN KEY ("profileId") REFERENCES "print-farm"."SchedulerConfigProfile"("id")
    ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "print-farm"."SchedulerScenarioCandidate"
    ADD CONSTRAINT "SchedulerScenarioCandidate_runId_fkey"
    FOREIGN KEY ("runId") REFERENCES "print-farm"."SchedulerScenarioRun"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
