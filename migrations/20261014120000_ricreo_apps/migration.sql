-- App Ricreo mostrate nel selettore app della sidebar (tabella condivisa
-- tra le app). Le righe iniziali replicano l'elenco di default del codice.

-- CreateTable
CREATE TABLE "public"."RicreoApp" (
    "id" UUID NOT NULL,
    "slug" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "url" TEXT NOT NULL,
    "logoUrl" TEXT,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "RicreoApp_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "RicreoApp_slug_key" ON "public"."RicreoApp"("slug");

-- Seed
INSERT INTO "public"."RicreoApp" ("id", "slug", "name", "url", "logoUrl", "sortOrder") VALUES
    (gen_random_uuid(), 'inventory', 'Ricreo Inventory', 'https://inventory.ricreo.app', 'https://inventory.ricreo.app/RI.svg', 10),
    (gen_random_uuid(), 'print-farm', 'Ricreo Print Farm', 'https://print-farm.ricreo.app', 'https://print-farm.ricreo.app/RF.svg', 20),
    (gen_random_uuid(), 'finance', 'Ricreo Finance', 'https://ricreo-finance.ricreo.app', 'https://ricreo-finance.ricreo.app/icons/icon-192.png', 30),
    (gen_random_uuid(), 'product-console', 'Product Console', 'https://product-console.ricreo.app', 'https://product-console.ricreo.app/logo.svg', 40),
    (gen_random_uuid(), 'preventivatore', 'Preventivatore', 'https://preventivatore.ricreo.app', 'https://preventivatore.ricreo.app/icon.svg', 50);

-- RLS: la tabella è letta solo dalle app via Prisma (utente postgres).
ALTER TABLE "public"."RicreoApp" ENABLE ROW LEVEL SECURITY;
