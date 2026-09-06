-- Prompt OpenAI modificabile e versioni titolo/bullet/descrizione per paese.
-- Le versioni pubblicate restano in archivio per verificare se Amazon le ha applicate.

CREATE TABLE IF NOT EXISTS "product"."QualityAiPrompt" (
  "id" TEXT NOT NULL,
  "key" TEXT NOT NULL,
  "prompt" JSONB NOT NULL,
  "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMPTZ(6) NOT NULL,

  CONSTRAINT "QualityAiPrompt_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "QualityAiPrompt_key_key"
  ON "product"."QualityAiPrompt" ("key");

CREATE TABLE IF NOT EXISTS "product"."QualityListingContentVersion" (
  "id" TEXT NOT NULL,
  "channel" "product"."StoreChannel" NOT NULL,
  "storeKey" TEXT NOT NULL,
  "countryCode" TEXT NOT NULL,
  "sku" TEXT NOT NULL,
  "version" INTEGER NOT NULL,
  "title" TEXT NOT NULL DEFAULT '',
  "description" TEXT NOT NULL DEFAULT '',
  "bulletPoints" JSONB NOT NULL,
  "published" BOOLEAN NOT NULL DEFAULT false,
  "publishedAt" TIMESTAMPTZ(6),
  "source" TEXT,
  "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMPTZ(6) NOT NULL,

  CONSTRAINT "QualityListingContentVersion_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "QualityListingContentVer_ver_key"
  ON "product"."QualityListingContentVersion" ("channel", "storeKey", "sku", "version");
CREATE INDEX IF NOT EXISTS "QualityListingContentVer_sku_pub"
  ON "product"."QualityListingContentVersion" ("sku", "storeKey", "published");

INSERT INTO "product"."QualityAiPrompt" ("id", "key", "prompt", "createdAt", "updatedAt")
VALUES (
  'cm_quality_listing_suggest',
  'listing-content-suggest',
  '{
    "model": "gpt-4o-mini",
    "system": "Sei un copywriter esperto di schede prodotto Amazon. Rispondi solo con JSON valido, senza markdown.",
    "instructions": [
      "Usa l''inserzione italiana come fonte di verità per traduzione e miglioramenti.",
      "Suggerisci miglioramenti in base ai criteri qualità: titolo oltre 150 caratteri e senza simboli/emoji; almeno 5 punti elenco, ognuno oltre 150 caratteri, prima lettera maiuscola, non tutti maiuscoli e senza icone; descrizione oltre 1000 caratteri.",
      "Non inventare caratteristiche assenti dall''inserzione italiana.",
      "Produci sia la versione in italiano (migliorata) sia la versione tradotta nella lingua del paese selezionato.",
      "Adatta tono e parole chiave al marketplace di destinazione, restando fedele al prodotto."
    ]
  }'::jsonb,
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
)
ON CONFLICT ("key") DO NOTHING;
