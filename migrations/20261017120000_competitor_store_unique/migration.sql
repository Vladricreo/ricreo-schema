-- Uno store (canale + storeId) appartiene a un solo venditore: blocca i doppioni
-- creati da import o form. Il controllo case-insensitive resta lato applicazione.

-- DropIndex
DROP INDEX IF EXISTS "product"."CompetitorChannel_channel_storeId_idx";

-- CreateIndex
CREATE UNIQUE INDEX "CompetitorChannel_channel_storeId_key" ON "product"."CompetitorChannel"("channel", "storeId");

-- Coppie con nome simile segnate "non sono lo stesso venditore".
-- CreateTable
CREATE TABLE "product"."CompetitorDuplicateDismissal" (
    "id" TEXT NOT NULL,
    "competitorAId" TEXT NOT NULL,
    "competitorBId" TEXT NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CompetitorDuplicateDismissal_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "CompetitorDuplicateDismissal_competitorAId_competitorBId_key" ON "product"."CompetitorDuplicateDismissal"("competitorAId", "competitorBId");

-- CreateIndex
CREATE INDEX "CompetitorDuplicateDismissal_competitorBId_idx" ON "product"."CompetitorDuplicateDismissal"("competitorBId");

-- AddForeignKey
ALTER TABLE "product"."CompetitorDuplicateDismissal" ADD CONSTRAINT "CompetitorDuplicateDismissal_competitorAId_fkey" FOREIGN KEY ("competitorAId") REFERENCES "product"."Competitor"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "product"."CompetitorDuplicateDismissal" ADD CONSTRAINT "CompetitorDuplicateDismissal_competitorBId_fkey" FOREIGN KEY ("competitorBId") REFERENCES "product"."Competitor"("id") ON DELETE CASCADE ON UPDATE CASCADE;
