-- Associazioni competitor: verdetto Jev sugli accoppiamenti (02/11).
--
-- «Calcola accoppiamenti» ora chiude con una fase di verifica: Jev (TypeSafe)
-- confronta titoli e foto di ogni coppia PENDING. Il verdetto resta sulla riga,
-- così un nuovo calcolo non rivaluta le coppie già viste; le coppie che Jev
-- giudica diverse con alta certezza escono dalla coda «da rivedere».
--
-- Idempotente e additiva: colonne facoltative con IF NOT EXISTS.

ALTER TABLE "product"."CompetitorListingMatchSuggestion"
  ADD COLUMN IF NOT EXISTS "jevScore" DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS "jevConfidence" DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS "jevPhotoScore" DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS "jevRejected" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS "jevCheckedAt" TIMESTAMPTZ(6);

CREATE INDEX IF NOT EXISTS "CompetitorListingMatchSuggestion_status_jevCheckedAt_idx"
  ON "product"."CompetitorListingMatchSuggestion"("status", "jevCheckedAt");
