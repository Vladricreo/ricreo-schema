-- ============================================================================
-- StoreFinanceEvent: eventi Finances Amazon non legati a un ordine.
--
-- La sync finanze (listFinancialEvents) leggeva solo Shipment / Refund /
-- GuaranteeClaim / Chargeback. Nella stessa risposta arrivano anche:
--   ADJUSTMENT  AdjustmentEventList: rimborsi e rettifiche (WAREHOUSE_LOST,
--               WAREHOUSE_DAMAGE, REVERSAL_REIMBURSEMENT, MISSING_FROM_INBOUND…)
--               una riga per AdjustmentItem (o per l'evento se senza item).
--   ADS         ProductAdsPaymentEventList: pubblicità addebitata sul saldo.
-- Importi con segno Amazon in valuta del marketplace; in EUR con
-- product.eur_factor(currency, "postedDate"::date). Upsert su idempotencyKey.
-- Letta da Ricreo Finance (finance.calcola_margine_ricostruito).
--
-- Solo oggetti nuovi, nessuna matview toccata: lock_timeout per non restare
-- in coda dietro un REFRESH in corso (meglio fallire e rilanciare).
-- ============================================================================

SET lock_timeout = '10s';

-- CreateEnum
CREATE TYPE "product"."StoreFinanceEventKind" AS ENUM ('ADJUSTMENT', 'ADS');

-- CreateTable
CREATE TABLE "product"."StoreFinanceEvent" (
    "id" TEXT NOT NULL,
    "channel" "product"."StoreChannel" NOT NULL,
    "storeKey" TEXT NOT NULL,
    "kind" "product"."StoreFinanceEventKind" NOT NULL,
    "type" TEXT NOT NULL,
    "postedDate" TIMESTAMPTZ(6) NOT NULL,
    "sku" TEXT,
    "quantity" INTEGER,
    "amount" DECIMAL(14,4) NOT NULL,
    "tax" DECIMAL(14,4) NOT NULL DEFAULT 0,
    "currency" TEXT NOT NULL,
    "reference" TEXT,
    "idempotencyKey" TEXT NOT NULL,
    "rawJson" JSONB NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "StoreFinanceEvent_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "StoreFinanceEvent_idempotencyKey_key" ON "product"."StoreFinanceEvent"("idempotencyKey");

-- CreateIndex
CREATE INDEX "StoreFinanceEvent_kind_posted_idx" ON "product"."StoreFinanceEvent"("channel", "kind", "postedDate");
