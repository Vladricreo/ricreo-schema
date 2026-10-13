-- Prima osservazione di un'issue Amazon (SKU × store × codice), conservata
-- a ogni sostituzione delle righe: serve a notificare solo le issue nuove
-- (conformità, soppressioni). Le righe già presenti restano NULL = note.

-- AlterTable
ALTER TABLE "product"."StoreListingIssue" ADD COLUMN "firstSeenAt" TIMESTAMPTZ(6);

-- CreateIndex
CREATE INDEX "StoreListingIssue_first_seen" ON "product"."StoreListingIssue" ("firstSeenAt");
