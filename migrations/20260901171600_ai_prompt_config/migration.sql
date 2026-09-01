-- Prompt OpenAI modificabili per categoria (import item / import documento).

-- CreateTable
CREATE TABLE "inventory"."AiPromptConfig" (
    "id" UUID NOT NULL,
    "key" TEXT NOT NULL,
    "model" TEXT NOT NULL,
    "reasoningEffort" TEXT NOT NULL,
    "intro" TEXT NOT NULL,
    "schemaText" TEXT NOT NULL,
    "points" JSONB NOT NULL,
    "userInstruction" TEXT NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AiPromptConfig_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "AiPromptConfig_key_key" ON "inventory"."AiPromptConfig"("key");
