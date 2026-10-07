-- Brand obbligatorio per singolo file (decisione utente 2026-10-07, punto 1;
-- REVISIONE 2026-09-30 V6-01).
--
-- Alcuni pezzi hanno file diversi per modelli di stampante diversi, ognuno col
-- suo brand: il file P1S/X1C stampa con un brand, il file X2D dello stesso pezzo
-- con un altro. Con `brandLocked = true` l'Item `materialId` della riga è un
-- vincolo duro: dashboard, prepare-start, compatible-spools e scheduler non lo
-- sostituiscono con la variante del gruppo di coerenza; senza scorta di
-- quell'Item il file non parte.
--
-- Default false = comportamento attuale (matching spec-first). Nessun backfill
-- qui: i 24 file candidati (12 pezzi, 07/10) li marca lo script
-- `client/scripts/backfill-2026-10-file-brand-lock.ts` dopo conferma.
--
-- Additiva e idempotente. Va applicata PRIMA del deploy del client: le query
-- Prisma con `include` su ProjectFileMaterial selezionano tutte le colonne.
ALTER TABLE "print-farm"."ProjectFileMaterial"
  ADD COLUMN IF NOT EXISTS "brandLocked" BOOLEAN NOT NULL DEFAULT false;
