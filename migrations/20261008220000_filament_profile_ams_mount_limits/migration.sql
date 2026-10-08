-- ============================================================================
-- Profilo filamento: limiti di montaggio in AMS (decisione utente 2026-10-08).
--
-- Perché: alcune bobine non si possono montare in AMS (troppo pesanti, o il
-- rocchetto non gira) e altre solo quando non sono piene: Smart Print
-- «Filamento abs+ nero» entra in AMS solo sotto l'80% del peso iniziale.
-- Le due opzioni si impostano da Print Farm, Impostazioni → Materiali, e
-- sono vincoli hard per montaggio (swap, runout), preparazione e scheduler.
--
-- - FilamentProfile.amsIncompatible: mai in AMS (default false).
-- - FilamentProfile.amsMaxFillPercent: in AMS solo con residuo ≤ X% del peso
--   iniziale; null = nessun limite. Ammessi 1..100.
--
-- Nessun dato toccato: colonna booleana con default false, colonna intera
-- nullable. Il valore per Smart Print lo imposta l'utente dalla pagina.
--
-- !! DEPLOY: applicare PRIMA del deploy di Print Farm (e di Inventory se
-- rigenera il client) !! Il client Prisma rigenerato legge le colonne in
-- ogni query su "FilamentProfile" senza select esplicita. Applicarla prima
-- è innocuo (il codice vecchio non le conosce).
-- ============================================================================

ALTER TABLE "print-farm"."FilamentProfile"
  ADD COLUMN "amsIncompatible" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN "amsMaxFillPercent" INTEGER;

ALTER TABLE "print-farm"."FilamentProfile"
  ADD CONSTRAINT "FilamentProfile_amsMaxFillPercent_range"
  CHECK ("amsMaxFillPercent" IS NULL OR ("amsMaxFillPercent" BETWEEN 1 AND 100));
