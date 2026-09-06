-- Esclusione operazioni dalle statistiche manodopera (audit + filtro nelle view costo).
-- Dopo migrate deploy, rieseguire anche prisma/migrations/sql/product_cost_views.sql
-- (le view filtrano excludedFromLaborStats).

-- AlterTable
ALTER TABLE "inventory"."AssemblyOperation"
ADD COLUMN "excludedFromLaborStats" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN "laborStatsExcludedAt" TIMESTAMPTZ(6),
ADD COLUMN "laborStatsExcludedByUserId" INTEGER,
ADD COLUMN "laborStatsExclusionReason" TEXT;

-- CreateIndex
CREATE INDEX "AssemblyOperation_operatorId_excludedFromLaborStats_idx"
ON "inventory"."AssemblyOperation"("operatorId", "excludedFromLaborStats");
