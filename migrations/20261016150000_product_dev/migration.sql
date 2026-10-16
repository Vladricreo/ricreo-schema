-- Sviluppo prodotti (Product Console): prodotti dall'idea al monitoraggio, file (foto, 3MF),
-- legame con le attività condivise di ogni fase, storico, responsabili e token per l'estensione Chrome.

-- CreateEnum
CREATE TYPE "product"."ProductDevStage" AS ENUM ('IDEA', 'REVIEW', 'DESIGN', 'CONTENT', 'PUBLISHING', 'MONITORING', 'IMPROVEMENT');

-- CreateEnum
CREATE TYPE "product"."ProductDevStatus" AS ENUM ('ACTIVE', 'PARKED', 'ARCHIVED');

-- CreateEnum
CREATE TYPE "product"."ProductDevFileKind" AS ENUM ('IMAGE', 'MODEL', 'DOCUMENT');

-- CreateTable
CREATE TABLE "product"."ProductDevItem" (
    "id" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "notes" TEXT NOT NULL DEFAULT '',
    "stage" "product"."ProductDevStage" NOT NULL DEFAULT 'IDEA',
    "status" "product"."ProductDevStatus" NOT NULL DEFAULT 'ACTIVE',
    "source" TEXT NOT NULL DEFAULT 'MANUAL',
    "sourceUrl" TEXT,
    "sourceSite" TEXT,
    "sourcePrice" DECIMAL(12,2),
    "sourceCurrency" TEXT,
    "opportunityId" TEXT,
    "coverFileId" TEXT,
    "reviewDecision" TEXT,
    "reviewNote" TEXT,
    "decidedById" INTEGER,
    "decidedAt" TIMESTAMPTZ(6),
    "targetPrice" DECIMAL(12,2),
    "channels" "product"."StoreChannel"[],
    "fulfillment" TEXT,
    "designerId" INTEGER,
    "designDueDate" DATE,
    "designNotes" TEXT NOT NULL DEFAULT '',
    "designDoneAt" TIMESTAMPTZ(6),
    "designDoneById" INTEGER,
    "ean" TEXT,
    "sku" TEXT,
    "links" JSONB NOT NULL DEFAULT '[]',
    "draftId" TEXT,
    "publishedAt" TIMESTAMPTZ(6),
    "productionQty" INTEGER,
    "productionDoneAt" TIMESTAMPTZ(6),
    "completedAt" TIMESTAMPTZ(6),
    "stageChangedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "sortOrder" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "createdById" INTEGER,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "ProductDevItem_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "product"."ProductDevFile" (
    "id" TEXT NOT NULL,
    "itemId" TEXT NOT NULL,
    "kind" "product"."ProductDevFileKind" NOT NULL,
    "stage" "product"."ProductDevStage" NOT NULL,
    "objectPath" TEXT,
    "externalUrl" TEXT,
    "fileName" TEXT NOT NULL,
    "contentType" TEXT,
    "size" INTEGER,
    "caption" TEXT,
    "uploadedById" INTEGER,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ProductDevFile_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "product"."ProductDevTask" (
    "id" TEXT NOT NULL,
    "itemId" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "stage" "product"."ProductDevStage" NOT NULL,
    "taskId" UUID NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ProductDevTask_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "product"."ProductDevEvent" (
    "id" TEXT NOT NULL,
    "itemId" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "stage" "product"."ProductDevStage",
    "message" TEXT NOT NULL,
    "data" JSONB,
    "userId" INTEGER,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ProductDevEvent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "product"."ProductDevSettings" (
    "id" TEXT NOT NULL DEFAULT 'default',
    "roles" JSONB NOT NULL DEFAULT '{}',
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "ProductDevSettings_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "product"."ConsoleApiToken" (
    "id" TEXT NOT NULL,
    "userId" INTEGER NOT NULL,
    "name" TEXT NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "prefix" TEXT NOT NULL,
    "lastUsedAt" TIMESTAMPTZ(6),
    "revokedAt" TIMESTAMPTZ(6),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ConsoleApiToken_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "ProductDevItem_board" ON "product"."ProductDevItem"("status", "stage", "sortOrder");

-- CreateIndex
CREATE INDEX "ProductDevItem_draft" ON "product"."ProductDevItem"("draftId");

-- CreateIndex
CREATE INDEX "ProductDevItem_opportunity" ON "product"."ProductDevItem"("opportunityId");

-- CreateIndex
CREATE INDEX "ProductDevFile_item" ON "product"."ProductDevFile"("itemId", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "ProductDevTask_item_kind" ON "product"."ProductDevTask"("itemId", "kind");

-- CreateIndex
CREATE INDEX "ProductDevTask_task" ON "product"."ProductDevTask"("taskId");

-- CreateIndex
CREATE INDEX "ProductDevEvent_item" ON "product"."ProductDevEvent"("itemId", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "ConsoleApiToken_tokenHash_key" ON "product"."ConsoleApiToken"("tokenHash");

-- CreateIndex
CREATE INDEX "ConsoleApiToken_user" ON "product"."ConsoleApiToken"("userId");

-- AddForeignKey
ALTER TABLE "product"."ProductDevFile" ADD CONSTRAINT "ProductDevFile_itemId_fkey" FOREIGN KEY ("itemId") REFERENCES "product"."ProductDevItem"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "product"."ProductDevTask" ADD CONSTRAINT "ProductDevTask_itemId_fkey" FOREIGN KEY ("itemId") REFERENCES "product"."ProductDevItem"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "product"."ProductDevEvent" ADD CONSTRAINT "ProductDevEvent_itemId_fkey" FOREIGN KEY ("itemId") REFERENCES "product"."ProductDevItem"("id") ON DELETE CASCADE ON UPDATE CASCADE;
