-- Tracciamento tempi operatore per cambio/ricarica filamento.

-- 1) Istante in cui la stampante ha iniziato ad aspettare l'operatore.
ALTER TABLE "print-farm"."Printer"
  ADD COLUMN IF NOT EXISTS "needsFilamentSwapAt" TIMESTAMPTZ(6);

-- Backfill: le stampanti gia' in attesa partono da adesso, cosi' il primo
-- calcolo di attesa non risulta nullo.
UPDATE "print-farm"."Printer"
SET "needsFilamentSwapAt" = NOW()
WHERE "needsFilamentSwap" = true
  AND "needsFilamentSwapAt" IS NULL;

-- 2) Sessione cronometrata di swap/runout.
CREATE TABLE "print-farm"."FilamentSwapSession" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "clientKey" TEXT NOT NULL,
    "printerId" UUID NOT NULL,
    "operatorUserId" INTEGER NOT NULL,
    "trigger" "print-farm"."FilamentLoadTrigger" NOT NULL DEFAULT 'SWAP',
    "targetKind" VARCHAR(10) NOT NULL DEFAULT 'external',
    "amsUnit" INTEGER,
    "slot" INTEGER,
    "extruderId" INTEGER,
    "fromSpoolId" UUID,
    "toSpoolId" UUID,
    "filamentLoadId" UUID,
    "detectedAt" TIMESTAMPTZ(6),
    "startedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lastStepAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "finishedAt" TIMESTAMPTZ(6),
    "waitSeconds" INTEGER,
    "elapsedSeconds" INTEGER,
    "workSeconds" INTEGER,
    "stepSeconds" JSONB,
    "errorCount" INTEGER NOT NULL DEFAULT 0,
    "abandoned" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "FilamentSwapSession_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "FilamentSwapSession_clientKey_key"
    ON "print-farm"."FilamentSwapSession"("clientKey");
CREATE INDEX "FilamentSwapSession_printerId_startedAt_idx"
    ON "print-farm"."FilamentSwapSession"("printerId", "startedAt" DESC);
CREATE INDEX "FilamentSwapSession_operatorUserId_startedAt_idx"
    ON "print-farm"."FilamentSwapSession"("operatorUserId", "startedAt" DESC);
CREATE INDEX "FilamentSwapSession_trigger_startedAt_idx"
    ON "print-farm"."FilamentSwapSession"("trigger", "startedAt" DESC);
CREATE INDEX "FilamentSwapSession_finishedAt_idx"
    ON "print-farm"."FilamentSwapSession"("finishedAt" DESC);

ALTER TABLE "print-farm"."FilamentSwapSession"
    ADD CONSTRAINT "FilamentSwapSession_printerId_fkey"
    FOREIGN KEY ("printerId") REFERENCES "print-farm"."Printer"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "print-farm"."FilamentSwapSession"
    ADD CONSTRAINT "FilamentSwapSession_operatorUserId_fkey"
    FOREIGN KEY ("operatorUserId") REFERENCES "public"."User"("id")
    ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "print-farm"."FilamentSwapSession"
    ADD CONSTRAINT "FilamentSwapSession_filamentLoadId_fkey"
    FOREIGN KEY ("filamentLoadId") REFERENCES "print-farm"."PrinterFilamentLoad"("id")
    ON DELETE SET NULL ON UPDATE CASCADE;

-- 3) View aggregate per la dashboard.
CREATE OR REPLACE VIEW "print_farm_views"."v_pf_filament_swap_time_30d" AS
SELECT
    s."trigger"::TEXT                                              AS "trigger",
    COUNT(*)::INT                                                  AS "sessionsCount",
    COUNT(*) FILTER (WHERE s."abandoned")::INT                     AS "abandonedCount",
    COALESCE(ROUND(AVG(s."workSeconds") FILTER (
        WHERE s."finishedAt" IS NOT NULL AND NOT s."abandoned"
    ), 2), 0)::NUMERIC(12, 2)                                      AS "avgWorkSeconds",
    COALESCE(ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY s."workSeconds"
    ) FILTER (
        WHERE s."finishedAt" IS NOT NULL AND NOT s."abandoned"
    )::NUMERIC, 2), 0)::NUMERIC(12, 2)                             AS "medianWorkSeconds",
    COALESCE(ROUND(AVG(s."waitSeconds") FILTER (
        WHERE s."waitSeconds" IS NOT NULL AND NOT s."abandoned"
    ), 2), 0)::NUMERIC(12, 2)                                      AS "avgWaitSeconds",
    COALESCE(SUM(s."workSeconds") FILTER (
        WHERE s."finishedAt" IS NOT NULL AND NOT s."abandoned"
    ), 0)::INT                                                     AS "totalWorkSeconds"
FROM "print-farm"."FilamentSwapSession" s
WHERE s."startedAt" >= NOW() - INTERVAL '30 days'
GROUP BY s."trigger";

CREATE OR REPLACE VIEW "print_farm_views"."v_pf_filament_swap_by_operator_30d" AS
SELECT
    s."operatorUserId"                                             AS "operatorUserId",
    COALESCE(NULLIF(TRIM(u."name"), ''), u."email", 'Operatore')   AS "operatorName",
    COUNT(*)::INT                                                  AS "sessionsCount",
    COUNT(*) FILTER (WHERE s."trigger" = 'RUNOUT')::INT            AS "runoutCount",
    COUNT(*) FILTER (WHERE s."trigger" = 'SWAP')::INT              AS "swapCount",
    COALESCE(ROUND(AVG(s."workSeconds") FILTER (
        WHERE s."finishedAt" IS NOT NULL AND NOT s."abandoned"
    ), 2), 0)::NUMERIC(12, 2)                                      AS "avgWorkSeconds"
FROM "print-farm"."FilamentSwapSession" s
JOIN "public"."User" u ON u."id" = s."operatorUserId"
WHERE s."startedAt" >= NOW() - INTERVAL '30 days'
GROUP BY s."operatorUserId", u."name", u."email";
