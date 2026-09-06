-- Soglie modificabili per le classi di esito delle coorti di lancio.
-- Solo schema product.

CREATE TABLE IF NOT EXISTS "product"."ListingLaunchThreshold" (
    "id" TEXT NOT NULL,
    "deadMaxUnits" INTEGER NOT NULL DEFAULT 1,
    "weakMaxUnits" INTEGER NOT NULL DEFAULT 4,
    "activatedMinUnits" INTEGER NOT NULL DEFAULT 5,
    "successfulMinUnits" INTEGER NOT NULL DEFAULT 10,
    "winnerMinUnits" INTEGER NOT NULL DEFAULT 25,
    "winnerMinRevenue" DECIMAL(12,2) NOT NULL DEFAULT 500,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ListingLaunchThreshold_pkey" PRIMARY KEY ("id")
);

INSERT INTO "product"."ListingLaunchThreshold" (
    "id",
    "deadMaxUnits",
    "weakMaxUnits",
    "activatedMinUnits",
    "successfulMinUnits",
    "winnerMinUnits",
    "winnerMinRevenue",
    "createdAt",
    "updatedAt"
)
VALUES ('default', 1, 4, 5, 10, 25, 500, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
ON CONFLICT ("id") DO NOTHING;
