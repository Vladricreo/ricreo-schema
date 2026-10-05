-- ============================================================================
-- Stato marketplace e rimborsi grezzi per i corrispettivi (Etsy).
--
-- Il CSV Etsy (base dei corrispettivi) esclude solo i receipt "Canceled".
-- Un annullo con accordo dopo il pagamento ("Fully Refunded", motivo cancel,
-- senza etichetta) per noi è Cancelled senza reso, ma per Etsy è vendita +
-- rimborso: se il rimborso cade nel mese dopo, i due mesi non tornavano.
--   - StoreOrderLine.channelStatus: receipt.status così come arriva;
--   - StoreOrderRefund: un rimborso per riga, importo e data esatti, fuori
--     dalla logica P&L di StoreReturnLine.
-- IF NOT EXISTS: applicata a mano su ricreo-db prima del deploy.
-- ============================================================================

ALTER TABLE "product"."StoreOrderLine"
  ADD COLUMN IF NOT EXISTS "channelStatus" TEXT;

CREATE TABLE IF NOT EXISTS "product"."StoreOrderRefund" (
  "id" TEXT NOT NULL,
  "channel" "product"."StoreChannel" NOT NULL,
  "storeKey" TEXT NOT NULL,
  "refundKey" TEXT NOT NULL,
  "orderId" TEXT NOT NULL,
  "amount" DECIMAL(12,2) NOT NULL,
  "currency" TEXT,
  "refundedAt" TIMESTAMPTZ(6) NOT NULL,
  "reason" TEXT,
  "status" TEXT,
  "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMPTZ(6) NOT NULL,
  CONSTRAINT "StoreOrderRefund_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "StoreOrderRefund_refundKey_key"
  ON "product"."StoreOrderRefund"("refundKey");
CREATE INDEX IF NOT EXISTS "StoreOrderRefund_channel_refundedAt_idx"
  ON "product"."StoreOrderRefund"("channel", "refundedAt");
CREATE INDEX IF NOT EXISTS "StoreOrderRefund_channel_orderId_idx"
  ON "product"."StoreOrderRefund"("channel", "orderId");
