-- Flag per escludere dal catalogo e dai fetch i prodotti concorrenti fuori interesse.
-- Solo schema product.

ALTER TABLE "product"."CompetitorProduct"
    ADD COLUMN "ignored" BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX "CompetitorProduct_competitorId_ignored_idx"
    ON "product"."CompetitorProduct"("competitorId", "ignored");

CREATE INDEX "CompetitorProduct_competitorChannelId_ignored_idx"
    ON "product"."CompetitorProduct"("competitorChannelId", "ignored");
