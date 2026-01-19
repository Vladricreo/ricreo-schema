-- CreateEnum
CREATE TYPE "inventory"."GuideStepMediaType" AS ENUM ('IMAGE', 'FILE', 'VIDEO');

-- CreateTable
CREATE TABLE "inventory"."GuideStep" (
    "id" UUID NOT NULL,
    "guideId" UUID NOT NULL,
    "parentId" UUID,
    "title" TEXT NOT NULL,
    "description" TEXT,
    "order" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "GuideStep_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."GuideStepMedia" (
    "id" UUID NOT NULL,
    "stepId" UUID NOT NULL,
    "type" "inventory"."GuideStepMediaType" NOT NULL DEFAULT 'IMAGE',
    "url" TEXT NOT NULL,
    "caption" TEXT,
    "order" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "GuideStepMedia_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."GuideStepTranslation" (
    "id" UUID NOT NULL,
    "stepId" UUID NOT NULL,
    "language" VARCHAR(10) NOT NULL,
    "sourceHash" VARCHAR(64) NOT NULL,
    "translatedTitle" TEXT NOT NULL,
    "translatedDescription" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "GuideStepTranslation_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "inventory"."GuideStepMediaTranslation" (
    "id" UUID NOT NULL,
    "mediaId" UUID NOT NULL,
    "language" VARCHAR(10) NOT NULL,
    "sourceHash" VARCHAR(64) NOT NULL,
    "translatedCaption" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "GuideStepMediaTranslation_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "GuideStep_guideId_idx" ON "inventory"."GuideStep"("guideId");

-- CreateIndex
CREATE INDEX "GuideStep_parentId_idx" ON "inventory"."GuideStep"("parentId");

-- CreateIndex
CREATE INDEX "GuideStepMedia_stepId_idx" ON "inventory"."GuideStepMedia"("stepId");

-- CreateIndex
CREATE INDEX "GuideStepTranslation_stepId_idx" ON "inventory"."GuideStepTranslation"("stepId");

-- CreateIndex
CREATE INDEX "GuideStepTranslation_language_idx" ON "inventory"."GuideStepTranslation"("language");

-- CreateIndex
CREATE UNIQUE INDEX "GuideStepTranslation_stepId_language_key" ON "inventory"."GuideStepTranslation"("stepId", "language");

-- CreateIndex
CREATE INDEX "GuideStepMediaTranslation_mediaId_idx" ON "inventory"."GuideStepMediaTranslation"("mediaId");

-- CreateIndex
CREATE INDEX "GuideStepMediaTranslation_language_idx" ON "inventory"."GuideStepMediaTranslation"("language");

-- CreateIndex
CREATE UNIQUE INDEX "GuideStepMediaTranslation_mediaId_language_key" ON "inventory"."GuideStepMediaTranslation"("mediaId", "language");

-- AddForeignKey
ALTER TABLE "inventory"."GuideStep" ADD CONSTRAINT "GuideStep_guideId_fkey" FOREIGN KEY ("guideId") REFERENCES "inventory"."Guide"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."GuideStep" ADD CONSTRAINT "GuideStep_parentId_fkey" FOREIGN KEY ("parentId") REFERENCES "inventory"."GuideStep"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."GuideStepMedia" ADD CONSTRAINT "GuideStepMedia_stepId_fkey" FOREIGN KEY ("stepId") REFERENCES "inventory"."GuideStep"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."GuideStepTranslation" ADD CONSTRAINT "GuideStepTranslation_stepId_fkey" FOREIGN KEY ("stepId") REFERENCES "inventory"."GuideStep"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "inventory"."GuideStepMediaTranslation" ADD CONSTRAINT "GuideStepMediaTranslation_mediaId_fkey" FOREIGN KEY ("mediaId") REFERENCES "inventory"."GuideStepMedia"("id") ON DELETE CASCADE ON UPDATE CASCADE;

