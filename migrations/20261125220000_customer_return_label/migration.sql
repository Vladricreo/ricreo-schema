-- Etichette di reso prepaid (25/11/2026): una riga per ogni tentativo di creare l'etichetta
-- di un reso presso il corriere (Sendcloud o ShippyPro). Il PDF sta nello Storage
-- (`labelObjectPath`); indirizzo, email e telefono del cliente non si salvano.
--
-- Due indici univoci parziali, non esprimibili nel modello Prisma:
--   * una sola etichetta attiva (non ERROR né CANCELLED) per reso;
--   * una sola creazione in corso (CREATING o TO_VERIFY) per spedizione.
-- `createdByUserId` è un id di User senza vincolo: l'etichetta resta se l'utente viene tolto.
--
-- Additiva: solo una tabella nuova, nessun dato esistente toccato, ripetibile. Va applicata
-- prima del deploy del client che la legge.
--
-- I vincoli verso CustomerReturn e Shipment chiedono un lock su tabelle molto usate: se non
-- arriva meglio fallire subito e rilanciare che accodare dietro tutto il resto.

SET lock_timeout = '10s';

CREATE TABLE IF NOT EXISTS "inventory"."CustomerReturnLabel" (
  "id"               UUID           NOT NULL DEFAULT gen_random_uuid(),
  "customerReturnId" UUID           NOT NULL,
  "shipmentId"       UUID,
  "attempt"          INTEGER        NOT NULL,
  "reference"        TEXT           NOT NULL,
  "provider"         TEXT           NOT NULL,
  "status"           TEXT           NOT NULL,
  "errorMessage"     TEXT,
  "serviceKey"       TEXT           NOT NULL,
  "serviceCode"      TEXT           NOT NULL,
  "serviceName"      TEXT           NOT NULL,
  "carrier"          TEXT           NOT NULL,
  "providerReturnId" TEXT,
  "providerParcelId" TEXT,
  "trackingNumber"   TEXT,
  "trackingUrl"      TEXT,
  "priceAmount"      DECIMAL(12, 2),
  "priceCurrency"    VARCHAR(3),
  "labelObjectPath"  TEXT,
  "createdByUserId"  INTEGER,
  "readyAt"          TIMESTAMPTZ(6),
  "cancelledAt"      TIMESTAMPTZ(6),
  "createdAt"        TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt"        TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "CustomerReturnLabel_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "CustomerReturnLabel_customerReturnId_fkey" FOREIGN KEY ("customerReturnId")
    REFERENCES "inventory"."CustomerReturn"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
  CONSTRAINT "CustomerReturnLabel_shipmentId_fkey" FOREIGN KEY ("shipmentId")
    REFERENCES "inventory"."Shipment"("id") ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT "CustomerReturnLabel_provider_check" CHECK ("provider" IN ('SENDCLOUD', 'SHIPPYPRO')),
  CONSTRAINT "CustomerReturnLabel_status_check" CHECK ("status" IN ('CREATING', 'READY', 'ERROR', 'TO_VERIFY', 'CANCEL_REQUESTED', 'CANCELLED'))
);

CREATE UNIQUE INDEX IF NOT EXISTS "CustomerReturnLabel_reference_key"
  ON "inventory"."CustomerReturnLabel"("reference");
CREATE INDEX IF NOT EXISTS "CustomerReturnLabel_customerReturnId_idx"
  ON "inventory"."CustomerReturnLabel"("customerReturnId");
CREATE INDEX IF NOT EXISTS "CustomerReturnLabel_trackingNumber_idx"
  ON "inventory"."CustomerReturnLabel"("trackingNumber");
CREATE INDEX IF NOT EXISTS "CustomerReturnLabel_providerReturnId_idx"
  ON "inventory"."CustomerReturnLabel"("providerReturnId");

-- Una sola etichetta attiva per reso: un secondo tentativo parte solo dopo errore o annullo.
CREATE UNIQUE INDEX IF NOT EXISTS "CustomerReturnLabel_return_active_key"
  ON "inventory"."CustomerReturnLabel"("customerReturnId") WHERE "status" NOT IN ('ERROR', 'CANCELLED');
-- Una sola creazione in corso per spedizione.
CREATE UNIQUE INDEX IF NOT EXISTS "CustomerReturnLabel_shipment_inflight_key"
  ON "inventory"."CustomerReturnLabel"("shipmentId") WHERE "status" IN ('CREATING', 'TO_VERIFY');

COMMENT ON TABLE "inventory"."CustomerReturnLabel" IS
  'Etichette di reso prepaid create presso il corriere, un tentativo per riga; il PDF sta nello Storage.';

-- Come le altre tabelle inventory: niente accesso da API, le app usano postgres/service_role.
ALTER TABLE "inventory"."CustomerReturnLabel" ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON "inventory"."CustomerReturnLabel" FROM anon, authenticated;
