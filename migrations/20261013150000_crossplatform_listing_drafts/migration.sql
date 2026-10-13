-- Listing crossplatform creati da zero: bozze resumable del wizard multi-store
-- (Amazon, eBay, Etsy, Temu) e esito per store con il controllo a 24 ore.

-- CreateEnum
CREATE TYPE "product"."CrossplatformListingDraftStatus" AS ENUM ('DRAFT', 'PARTIAL', 'PUBLISHED', 'ARCHIVED');

-- CreateTable
CREATE TABLE "product"."CrossplatformListingDraft" (
    "id" TEXT NOT NULL,
    "sku" TEXT NOT NULL DEFAULT '',
    "title" TEXT NOT NULL DEFAULT '',
    "status" "product"."CrossplatformListingDraftStatus" NOT NULL DEFAULT 'DRAFT',
    "channels" "product"."StoreChannel"[],
    "currentStep" TEXT NOT NULL DEFAULT 'product',
    "data" JSONB NOT NULL DEFAULT '{}',
    "coverPath" TEXT,
    "createdById" INTEGER,
    "createdByName" TEXT,
    "publishedAt" TIMESTAMPTZ(6),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "CrossplatformListingDraft_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "product"."CrossplatformListingDraftPublication" (
    "id" TEXT NOT NULL,
    "draftId" TEXT NOT NULL,
    "channel" "product"."StoreChannel" NOT NULL,
    "storeKey" TEXT NOT NULL DEFAULT '',
    "status" TEXT NOT NULL,
    "externalId" TEXT,
    "submissionId" TEXT,
    "error" TEXT,
    "issues" JSONB,
    "submittedAt" TIMESTAMPTZ(6) NOT NULL,
    "checkDueAt" TIMESTAMPTZ(6),
    "checkAttempts" INTEGER NOT NULL DEFAULT 0,
    "checkStatus" TEXT,
    "checkMessage" TEXT,
    "checkedAt" TIMESTAMPTZ(6),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "CrossplatformListingDraftPublication_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "CrossplatformListingDraft_status" ON "product"."CrossplatformListingDraft"("status", "updatedAt");

-- CreateIndex
CREATE INDEX "CrossplatformListingDraft_sku" ON "product"."CrossplatformListingDraft"("sku");

-- CreateIndex
CREATE UNIQUE INDEX "CrossplatformListingDraftPublication_draft_channel" ON "product"."CrossplatformListingDraftPublication"("draftId", "channel");

-- CreateIndex
CREATE INDEX "CrossplatformListingDraftPublication_check_due" ON "product"."CrossplatformListingDraftPublication"("checkDueAt");

-- AddForeignKey
ALTER TABLE "product"."CrossplatformListingDraftPublication" ADD CONSTRAINT "CrossplatformListingDraftPublication_draftId_fkey" FOREIGN KEY ("draftId") REFERENCES "product"."CrossplatformListingDraft"("id") ON DELETE CASCADE ON UPDATE CASCADE;
