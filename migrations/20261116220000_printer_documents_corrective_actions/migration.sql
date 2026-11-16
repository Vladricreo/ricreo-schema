-- A-413 (16/11): documenti della stampante o del modello (fattura, manuale,
-- dichiarazione CE, garanzia, altro; file caricato o link, es. wiki Bambu) e azioni
-- correttive sui problemi ricorrenti.
-- Tabelle nuove. La fattura già caricata su Printer (A-406) viene copiata come
-- documento INVOICE; le colonne purchaseInvoice* restano ma il codice non le usa più.

-- CreateTable
CREATE TABLE "print-farm"."PrinterDocument" (
    "id" UUID NOT NULL,
    "printerId" UUID,
    "printerModelId" INTEGER,
    "kind" VARCHAR(20) NOT NULL,
    "title" VARCHAR(200) NOT NULL,
    "fileKey" TEXT,
    "fileName" VARCHAR(255),
    "contentType" VARCHAR(100),
    "sizeBytes" INTEGER,
    "externalUrl" VARCHAR(1000),
    "documentDate" DATE,
    "validUntil" DATE,
    "uploadedBy" VARCHAR(120),
    "uploadedById" INTEGER,
    "deletedAt" TIMESTAMPTZ(6),
    "deletedBy" VARCHAR(120),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PrinterDocument_pkey" PRIMARY KEY ("id"),
    -- Esattamente uno fra stampante e modello.
    CONSTRAINT "PrinterDocument_owner_check" CHECK (("printerId" IS NULL) <> ("printerModelId" IS NULL)),
    -- Un file oppure un link (es. pagina della wiki Bambu), non tutti e due.
    CONSTRAINT "PrinterDocument_source_check" CHECK (("fileKey" IS NULL) <> ("externalUrl" IS NULL))
);

-- CreateTable
CREATE TABLE "print-farm"."MaintenanceCorrectiveAction" (
    "id" UUID NOT NULL,
    "printerId" UUID NOT NULL,
    "issueCategoryId" UUID,
    "problem" VARCHAR(200) NOT NULL,
    "occurrences" INTEGER NOT NULL DEFAULT 0,
    "windowDays" INTEGER NOT NULL DEFAULT 90,
    "cause" TEXT,
    "action" TEXT NOT NULL,
    "status" VARCHAR(12) NOT NULL DEFAULT 'OPEN',
    "createdBy" VARCHAR(120),
    "closedAt" TIMESTAMPTZ(6),
    "closedBy" VARCHAR(120),
    "effective" BOOLEAN,
    "effectivenessNote" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "MaintenanceCorrectiveAction_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "PrinterDocument_printerId_deletedAt_idx" ON "print-farm"."PrinterDocument"("printerId", "deletedAt");

-- CreateIndex
CREATE INDEX "PrinterDocument_printerModelId_deletedAt_idx" ON "print-farm"."PrinterDocument"("printerModelId", "deletedAt");

-- CreateIndex
CREATE INDEX "MaintenanceCorrectiveAction_printerId_status_idx" ON "print-farm"."MaintenanceCorrectiveAction"("printerId", "status");

-- CreateIndex
CREATE INDEX "MaintenanceCorrectiveAction_issueCategoryId_idx" ON "print-farm"."MaintenanceCorrectiveAction"("issueCategoryId");

-- AddForeignKey
ALTER TABLE "print-farm"."PrinterDocument" ADD CONSTRAINT "PrinterDocument_printerId_fkey" FOREIGN KEY ("printerId") REFERENCES "print-farm"."Printer"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."PrinterDocument" ADD CONSTRAINT "PrinterDocument_printerModelId_fkey" FOREIGN KEY ("printerModelId") REFERENCES "print-farm"."PrinterModel"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."MaintenanceCorrectiveAction" ADD CONSTRAINT "MaintenanceCorrectiveAction_printerId_fkey" FOREIGN KEY ("printerId") REFERENCES "print-farm"."Printer"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."MaintenanceCorrectiveAction" ADD CONSTRAINT "MaintenanceCorrectiveAction_issueCategoryId_fkey" FOREIGN KEY ("issueCategoryId") REFERENCES "print-farm"."MaintenanceCategory"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- Lette e scritte solo via Prisma (postgres, proprietario): RLS senza policy chiude l'accesso anon.
ALTER TABLE "print-farm"."PrinterDocument" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "print-farm"."MaintenanceCorrectiveAction" ENABLE ROW LEVEL SECURITY;

-- Fatture già caricate (A-406) → documenti INVOICE.
INSERT INTO "print-farm"."PrinterDocument"
  ("id", "printerId", "kind", "title", "fileKey", "fileName", "contentType", "sizeBytes", "createdAt", "updatedAt")
SELECT gen_random_uuid(), p."id", 'INVOICE', 'Fattura d''acquisto', p."purchaseInvoiceKey",
       COALESCE(p."purchaseInvoiceName", 'fattura'),
       CASE lower(substring(p."purchaseInvoiceKey" from '\.([^.]+)$'))
         WHEN 'pdf' THEN 'application/pdf' WHEN 'png' THEN 'image/png'
         WHEN 'webp' THEN 'image/webp' ELSE 'image/jpeg' END,
       0, COALESCE(p."purchaseInvoiceAt", now()), now()
  FROM "print-farm"."Printer" p
 WHERE p."purchaseInvoiceKey" IS NOT NULL;
