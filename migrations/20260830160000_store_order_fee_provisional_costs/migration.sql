-- Commissioni e spedizione provvisorie su StoreOrderFee:
-- le colonne esistenti restano solo-reali; le stime vanno sulle provisional*.

ALTER TABLE product."StoreOrderFee"
  ADD COLUMN IF NOT EXISTS "provisionalReferralFee" DECIMAL(12, 4) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "provisionalDigitalServicesFee" DECIMAL(12, 4) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "provisionalFbaFee" DECIMAL(12, 4) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "provisionalShippingChargeback" DECIMAL(12, 4) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "provisionalFbmShipping" DECIMAL(12, 4) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS "provisionalFeeSource" TEXT,
  ADD COLUMN IF NOT EXISTS "provisionalShippingSource" TEXT,
  ADD COLUMN IF NOT EXISTS "provisionalAt" TIMESTAMPTZ(6),
  ADD COLUMN IF NOT EXISTS "realCosts" BOOLEAN NOT NULL DEFAULT false;

-- Righe già postate da Finances / marketplace: costi reali.
UPDATE product."StoreOrderFee"
SET "realCosts" = true
WHERE "postedDate" IS NOT NULL
  AND "realCosts" = false;

-- Righe non postate (Product Fees, default Temu): sposta i valori nelle colonne provvisorie.
UPDATE product."StoreOrderFee"
SET
  "provisionalReferralFee" = "referralFee",
  "provisionalDigitalServicesFee" = "digitalServicesFee",
  "provisionalFbaFee" = "fbaFulfillmentFee",
  "provisionalShippingChargeback" = "shippingChargeback",
  "provisionalFeeSource" = CASE
    WHEN channel = 'AMAZON' THEN 'fee_preview'
    ELSE 'channel_settings'
  END,
  "provisionalAt" = COALESCE("updatedAt", CURRENT_TIMESTAMP),
  "referralFee" = 0,
  "digitalServicesFee" = 0,
  "fbaFulfillmentFee" = 0,
  "shippingChargeback" = 0,
  "refundCommission" = 0,
  "otherFee" = 0,
  "realCosts" = false
WHERE "postedDate" IS NULL
  AND (
    "referralFee" <> 0
    OR "digitalServicesFee" <> 0
    OR "fbaFulfillmentFee" <> 0
    OR "shippingChargeback" <> 0
    OR "otherFee" <> 0
  );

CREATE INDEX IF NOT EXISTS "StoreOrderFee_provisional_idx"
  ON product."StoreOrderFee" (channel, "realCosts")
  WHERE "realCosts" = false;
