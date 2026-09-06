-- Prepara Shipment per la cifratura applicativa AES-256-GCM dei dati personali.
-- Il backfill del contenuto esistente viene eseguito separatamente perché
-- richiede PII_ENCRYPTION_KEY, che non deve essere esposta a Postgres.

ALTER TABLE "inventory"."Shipment"
ADD COLUMN "recipientNameHash" VARCHAR(64);

COMMENT ON COLUMN "inventory"."Shipment"."recipientNameHash" IS
'Blind index HMAC-SHA256 del nome destinatario normalizzato; non contiene il nome in chiaro.';

CREATE INDEX "Shipment_recipientNameHash_idx"
ON "inventory"."Shipment"("recipientNameHash");
