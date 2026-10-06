-- Cron import inserzioni eBay a ciclo: ordine per ultimo passaggio (più vecchio prima)
-- e conferma utente per gli store oltre la soglia del primo import.
ALTER TABLE "product"."CompetitorChannel"
  ADD COLUMN IF NOT EXISTS "cronCheckedAt" TIMESTAMPTZ(6),
  ADD COLUMN IF NOT EXISTS "largeImportApprovedAt" TIMESTAMPTZ(6),
  ADD COLUMN IF NOT EXISTS "largeImportApprovedByUserId" INTEGER;

-- Notifiche "Import eBay da confermare" già inviate: tipo e canale nel JSON,
-- così la pagina notifiche mostra il bottone di conferma anche su quelle.
UPDATE "product"."ConsoleNotification"
SET "data" = COALESCE("data", '{}'::jsonb) || jsonb_build_object(
  'kind', 'ebay-large-import',
  'competitorChannelId', split_part("dedupeKey", ':', 3)
)
WHERE "dedupeKey" LIKE 'competitor:ebay-first-import:%';
