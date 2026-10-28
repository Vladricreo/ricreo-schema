-- Piatti combinati (S-188, A-165): grammi per filamento di ogni oggetto del piatto,
-- letti dal G-code all'upload. Consumo bobine e piano bobine dei piatti combinati con
-- oggetti saltati usano i grammi degli oggetti stampati davvero invece di dividere il
-- peso del file in parti uguali. Solo aggiunta, nullable.
ALTER TABLE "print-farm"."ProjectFileObject" ADD COLUMN "filamentGrams" JSONB;
