-- Titolo breve dei codici errore (14/10/2026): mostrato in Impostazioni → Errori,
-- nelle schede errore delle stampanti e nelle proposte AI. Additiva: colonna nullable,
-- i titoli dei codici già a catalogo li scrive `scripts/backfill-2026-10-titoli-errori.ts`.
-- AlterTable
ALTER TABLE "print-farm"."ErrorCode" ADD COLUMN     "title" TEXT;
