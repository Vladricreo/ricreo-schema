-- A-410 (16/11): moduli hardware della stampante da `info.get_version`
-- (scheda principale, testina, AMS, FTS, ...) con numero di serie e versioni.
-- Tabella nuova, nessun dato esistente toccato. La scrive il backend quando la
-- lista dei moduli cambia; finché la tabella manca il backend lo segna e va avanti.

-- CreateTable
CREATE TABLE "print-farm"."PrinterHardwareModule" (
    "id" UUID NOT NULL,
    "printerId" UUID NOT NULL,
    "name" VARCHAR(64) NOT NULL,
    "serialNumber" VARCHAR(80) NOT NULL DEFAULT '',
    "hwVersion" VARCHAR(80),
    "swVersion" VARCHAR(80),
    "productName" VARCHAR(120),
    "projectName" VARCHAR(120),
    "raw" JSONB,
    "isCurrent" BOOLEAN NOT NULL DEFAULT true,
    "firstSeenAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lastSeenAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "removedAt" TIMESTAMPTZ(6),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PrinterHardwareModule_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "PrinterHardwareModule_printerId_name_serialNumber_key" ON "print-farm"."PrinterHardwareModule"("printerId", "name", "serialNumber");

-- CreateIndex
CREATE INDEX "PrinterHardwareModule_printerId_isCurrent_idx" ON "print-farm"."PrinterHardwareModule"("printerId", "isCurrent");

-- AddForeignKey
ALTER TABLE "print-farm"."PrinterHardwareModule" ADD CONSTRAINT "PrinterHardwareModule_printerId_fkey" FOREIGN KEY ("printerId") REFERENCES "print-farm"."Printer"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Letta via Prisma e scritta dal backend (postgres, proprietario): RLS senza policy chiude l'accesso anon.
ALTER TABLE "print-farm"."PrinterHardwareModule" ENABLE ROW LEVEL SECURITY;
