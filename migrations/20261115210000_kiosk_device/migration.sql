-- Tablet del kiosk (15/11, S-264, A-370): token del dispositivo generato da
-- Impostazioni → Kiosk. Si salva solo l'hash SHA-256 (hex) del token.
-- Tabella nuova, nessun dato esistente toccato. Va applicata prima del deploy
-- del client che la legge (`/api/kiosk/backend-token`, Impostazioni → Kiosk).

-- CreateTable
CREATE TABLE "print-farm"."KioskDevice" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "name" TEXT NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "enabled" BOOLEAN NOT NULL DEFAULT true,
    "lastSeenAt" TIMESTAMPTZ(6),
    "createdById" INTEGER,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "KioskDevice_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "KioskDevice_tokenHash_key" ON "print-farm"."KioskDevice"("tokenHash");

-- Niente accesso dalla Data API (anon/authenticated): gli hash restano al server.
ALTER TABLE "print-farm"."KioskDevice" ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE "print-farm"."KioskDevice" FROM anon, authenticated;
