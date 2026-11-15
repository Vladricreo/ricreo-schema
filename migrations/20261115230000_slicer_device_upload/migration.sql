-- PC di slicing e file in attesa (15/11, R-215): il plugin OrcaSlicer deposita i
-- `.gcode.3mf` esportati con il token del PC, generato da Impostazioni → Slicer.
-- Si salva solo l'hash SHA-256 (hex) del token.
-- Due tabelle nuove, nessun dato esistente toccato. Va applicata prima del deploy
-- del client che le legge (`/api/slicer/uploads`, Impostazioni → Slicer).

-- CreateTable
CREATE TABLE "print-farm"."SlicerDevice" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "name" TEXT NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "enabled" BOOLEAN NOT NULL DEFAULT true,
    "lastSeenAt" TIMESTAMPTZ(6),
    "createdById" INTEGER,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SlicerDevice_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "print-farm"."SlicerUpload" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "deviceId" UUID NOT NULL,
    "filename" TEXT NOT NULL,
    "storageKey" TEXT NOT NULL,
    "sizeBytes" INTEGER NOT NULL,
    "projectName" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SlicerUpload_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "SlicerDevice_tokenHash_key" ON "print-farm"."SlicerDevice"("tokenHash");

-- CreateIndex
CREATE INDEX "SlicerUpload_createdAt_idx" ON "print-farm"."SlicerUpload"("createdAt");

-- CreateIndex
CREATE INDEX "SlicerUpload_deviceId_idx" ON "print-farm"."SlicerUpload"("deviceId");

-- AddForeignKey
ALTER TABLE "print-farm"."SlicerUpload" ADD CONSTRAINT "SlicerUpload_deviceId_fkey" FOREIGN KEY ("deviceId") REFERENCES "print-farm"."SlicerDevice"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Niente accesso dalla Data API (anon/authenticated): hash e file restano al server.
ALTER TABLE "print-farm"."SlicerDevice" ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE "print-farm"."SlicerDevice" FROM anon, authenticated;
ALTER TABLE "print-farm"."SlicerUpload" ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE "print-farm"."SlicerUpload" FROM anon, authenticated;
