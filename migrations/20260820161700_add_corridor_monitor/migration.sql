-- Monitor TV di corridoio: un kiosk pubblico per aisleCode, con vista proiettata.
CREATE TABLE "print-farm"."CorridorMonitor" (
    "id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "aisleCode" TEXT NOT NULL,
    "publicToken" TEXT NOT NULL,
    "activeMode" TEXT NOT NULL DEFAULT 'default',
    "harvestPlan" JSONB,
    "projectedAt" TIMESTAMPTZ(6),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "CorridorMonitor_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "CorridorMonitor_aisleCode_key" ON "print-farm"."CorridorMonitor"("aisleCode");
CREATE UNIQUE INDEX "CorridorMonitor_publicToken_key" ON "print-farm"."CorridorMonitor"("publicToken");
