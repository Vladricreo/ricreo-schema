-- Fatture corriere (UPS) importate da CSV per l'analisi costi spedizione reali.
-- Testata documento (fattura / nota di credito) + righe di addebito per tracking.
-- Il collegamento agli ordini avviene in lettura (tracking → inventory.Shipment /
-- SendcloudParcel → ordine marketplace): nessuna modifica a inventory.

-- CreateEnum
CREATE TYPE "product"."CarrierCode" AS ENUM ('UPS');

-- CreateEnum
CREATE TYPE "product"."CarrierInvoiceKind" AS ENUM ('INVOICE', 'CREDIT_NOTE');

-- CreateEnum
CREATE TYPE "product"."CarrierChargeType" AS ENUM ('FREIGHT', 'FUEL', 'SURCHARGE', 'ADJUSTMENT', 'RETURN', 'PICKUP', 'CREDIT', 'TAX', 'INFO', 'OTHER');

-- CreateTable
CREATE TABLE "product"."CarrierInvoice" (
    "id" UUID NOT NULL,
    "carrier" "product"."CarrierCode" NOT NULL DEFAULT 'UPS',
    "kind" "product"."CarrierInvoiceKind" NOT NULL DEFAULT 'INVOICE',
    "invoiceNumber" TEXT NOT NULL,
    "accountNumber" TEXT,
    "invoiceDate" DATE NOT NULL,
    "dueDate" DATE,
    "currency" VARCHAR(3) NOT NULL DEFAULT 'EUR',
    "totalAmount" DECIMAL(12,2) NOT NULL,
    "netAmount" DECIMAL(12,2) NOT NULL,
    "taxAmount" DECIMAL(12,2) NOT NULL,
    "fileName" TEXT,
    "uploadedByUserId" INTEGER,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CarrierInvoice_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "product"."CarrierInvoiceCharge" (
    "id" UUID NOT NULL,
    "invoiceId" UUID NOT NULL,
    "lineNo" INTEGER NOT NULL,
    "trackingNumber" TEXT,
    "leadTrackingNumber" TEXT,
    "reference" TEXT,
    "transactionDate" DATE,
    "type" "product"."CarrierChargeType" NOT NULL,
    "categoryCode" TEXT,
    "categoryDetailCode" TEXT,
    "classCode" TEXT,
    "chargeCode" TEXT,
    "description" TEXT,
    "netAmount" DECIMAL(12,2) NOT NULL,
    "incentiveAmount" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "enteredWeightKg" DECIMAL(8,2),
    "billedWeightKg" DECIMAL(8,2),
    "zone" TEXT,
    "packageDimensions" TEXT,
    "receiverCountry" VARCHAR(2),
    "receiverPostalCode" TEXT,
    "receiverCity" TEXT,
    "note" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "CarrierInvoiceCharge_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "CarrierInvoice_invoiceDate_idx" ON "product"."CarrierInvoice"("invoiceDate");

-- CreateIndex
CREATE UNIQUE INDEX "CarrierInvoice_carrier_invoiceNumber_key" ON "product"."CarrierInvoice"("carrier", "invoiceNumber");

-- CreateIndex
CREATE INDEX "CarrierInvoiceCharge_invoiceId_idx" ON "product"."CarrierInvoiceCharge"("invoiceId");

-- CreateIndex
CREATE INDEX "CarrierInvoiceCharge_trackingNumber_idx" ON "product"."CarrierInvoiceCharge"("trackingNumber");

-- CreateIndex
CREATE INDEX "CarrierInvoiceCharge_leadTrackingNumber_idx" ON "product"."CarrierInvoiceCharge"("leadTrackingNumber");

-- CreateIndex
CREATE INDEX "CarrierInvoiceCharge_reference_idx" ON "product"."CarrierInvoiceCharge"("reference");

-- CreateIndex
CREATE INDEX "CarrierInvoiceCharge_transactionDate_idx" ON "product"."CarrierInvoiceCharge"("transactionDate");

-- AddForeignKey
ALTER TABLE "product"."CarrierInvoiceCharge" ADD CONSTRAINT "CarrierInvoiceCharge_invoiceId_fkey" FOREIGN KEY ("invoiceId") REFERENCES "product"."CarrierInvoice"("id") ON DELETE CASCADE ON UPDATE CASCADE;
