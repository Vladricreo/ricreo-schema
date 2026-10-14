-- Accesso degli utenti alle app Ricreo: decide quali app compaiono nel
-- selettore. Regola: app corrente + app attive con una riga per l'utente;
-- un utente senza righe vede solo l'app corrente.

-- CreateTable
CREATE TABLE "public"."RicreoAppAccess" (
    "userId" INTEGER NOT NULL,
    "appId" UUID NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "RicreoAppAccess_pkey" PRIMARY KEY ("userId","appId")
);

-- CreateIndex
CREATE INDEX "RicreoAppAccess_appId_idx" ON "public"."RicreoAppAccess"("appId");

-- AddForeignKey
ALTER TABLE "public"."RicreoAppAccess" ADD CONSTRAINT "RicreoAppAccess_userId_fkey" FOREIGN KEY ("userId") REFERENCES "public"."User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "public"."RicreoAppAccess" ADD CONSTRAINT "RicreoAppAccess_appId_fkey" FOREIGN KEY ("appId") REFERENCES "public"."RicreoApp"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Seed (14/10/2026): Vlad, Adriana Ionescu, Nicola Colombo, Matteo Colombo
-- → tutte le app; Davide Brancati, Akter Bilkis → inventory e print-farm.
INSERT INTO "public"."RicreoAppAccess" ("userId", "appId")
SELECT u."id", a."id"
FROM "public"."User" u
CROSS JOIN "public"."RicreoApp" a
WHERE u."username" IN ('vlad', 'adriana', 'Nick', 'matteo')
   OR (u."username" IN ('davide', 'bilkiss') AND a."slug" IN ('inventory', 'print-farm'))
ON CONFLICT DO NOTHING;

-- RLS: la tabella è letta solo dalle app via Prisma (utente postgres).
ALTER TABLE "public"."RicreoAppAccess" ENABLE ROW LEVEL SECURITY;
