-- Ricerca titoli in «Collega listing»: ILIKE sul catalogo concorrenti.
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- CreateIndex
CREATE INDEX "CompetitorProduct_title_trgm_idx" ON "product"."CompetitorProduct" USING GIN ("title" gin_trgm_ops);
