-- Import qualità Amazon: token della prossima pagina listing, così il giro
-- successivo riprende da lì invece di risfogliare da pagina 1.

-- AlterTable
ALTER TABLE "product"."StoreQualityDailyJob" ADD COLUMN "nextPageToken" TEXT;
