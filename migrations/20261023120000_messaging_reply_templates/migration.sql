-- Risposte pronte della messaggistica: testo italiano con variabili + traduzioni per lingua.
CREATE TABLE "product"."MessagingReplyTemplate" (
    "id" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "bodyIt" TEXT NOT NULL,
    "version" INTEGER NOT NULL DEFAULT 1,
    "updatedByName" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "MessagingReplyTemplate_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "product"."MessagingReplyTemplateTranslation" (
    "id" TEXT NOT NULL,
    "templateId" TEXT NOT NULL,
    "lang" TEXT NOT NULL,
    "body" TEXT NOT NULL,
    "sourceVersion" INTEGER NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "MessagingReplyTemplateTranslation_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "MessagingReplyTemplateTranslation_lang" ON "product"."MessagingReplyTemplateTranslation"("templateId", "lang");

ALTER TABLE "product"."MessagingReplyTemplateTranslation" ADD CONSTRAINT "MessagingReplyTemplateTranslation_templateId_fkey" FOREIGN KEY ("templateId") REFERENCES "product"."MessagingReplyTemplate"("id") ON DELETE CASCADE ON UPDATE CASCADE;
