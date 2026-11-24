-- Disegno tecnico quotato dal 3MF del prodotto (24/11/2026) e sua pubblicazione su Amazon.
--
-- 1. ProductTechnicalDrawing: versioni del disegno di un prodotto. Oggi si salvano solo
--    disegni con le linee calcolate dal 3MF (`source = 'BASE'`, `status = 'DONE'`). Le
--    colonne `status`, `error`, `linesUrl`, `prompt` e `model` e l'indice univoco sui
--    lavori in corso servono alle linee fatte con l'AI, facoltative e rimandate
--    [utente 24/11], così non serve una seconda migrazione.
-- 2. ProductTechnicalDrawingPublication: invii del disegno come foto dell'inserzione
--    Amazon, una riga per SKU e paese di ogni pubblicazione (`batchId`). `slot` e
--    `imageUrl` restano vuoti se l'invio non arriva a sceglierli.
--
-- I file stanno nello Storage sotto `technical-drawings/<productId>/`. Gli id utente
-- (`createdById`) non hanno vincolo: il disegno resta se l'utente viene tolto.
--
-- Additiva: solo tabelle nuove, nessun dato esistente toccato, ripetibile. Va applicata
-- prima del deploy del client che la legge.
--
-- Il vincolo verso Product chiede un lock su una tabella molto usata: se non arriva
-- meglio fallire subito e rilanciare che accodare dietro tutto il resto.

SET lock_timeout = '10s';

CREATE TABLE IF NOT EXISTS "inventory"."ProductTechnicalDrawing" (
  "id"          UUID           NOT NULL DEFAULT gen_random_uuid(),
  "productId"   UUID           NOT NULL,
  "status"      TEXT           NOT NULL,
  "error"       TEXT,
  "source"      TEXT           NOT NULL,
  "baseUrl"     TEXT,
  "linesUrl"    TEXT,
  "finalUrl"    TEXT,
  "choices"     JSONB          NOT NULL,
  "prompt"      TEXT,
  "model"       TEXT,
  "treemfUrl"   TEXT           NOT NULL,
  "createdById" INTEGER        NOT NULL,
  "createdAt"   TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt"   TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "deletedAt"   TIMESTAMPTZ(6),
  CONSTRAINT "ProductTechnicalDrawing_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "ProductTechnicalDrawing_productId_fkey" FOREIGN KEY ("productId")
    REFERENCES "inventory"."Product"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "ProductTechnicalDrawing_status_check" CHECK ("status" IN ('RUNNING', 'DONE', 'FAILED')),
  CONSTRAINT "ProductTechnicalDrawing_source_check" CHECK ("source" IN ('AI', 'BASE'))
);

CREATE INDEX IF NOT EXISTS "ProductTechnicalDrawing_productId_createdAt_idx"
  ON "inventory"."ProductTechnicalDrawing"("productId", "createdAt");

-- Un solo lavoro in corso per prodotto: due avvii insieme non pagano due generazioni.
CREATE UNIQUE INDEX IF NOT EXISTS "ProductTechnicalDrawing_productId_running_key"
  ON "inventory"."ProductTechnicalDrawing"("productId")
  WHERE "status" = 'RUNNING';

CREATE TABLE IF NOT EXISTS "inventory"."ProductTechnicalDrawingPublication" (
  "id"            UUID           NOT NULL DEFAULT gen_random_uuid(),
  "drawingId"     UUID           NOT NULL,
  "batchId"       UUID           NOT NULL,
  "asin"          TEXT           NOT NULL,
  "skuCode"       TEXT           NOT NULL,
  "marketplaceId" TEXT           NOT NULL,
  "slot"          TEXT,
  "imageUrl"      TEXT,
  "previousUrl"   TEXT,
  "previewHash"   TEXT,
  "status"        TEXT           NOT NULL,
  "error"         TEXT,
  "submissionId"  TEXT,
  "createdById"   INTEGER        NOT NULL,
  "createdAt"     TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt"     TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "ProductTechnicalDrawingPublication_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "ProductTechnicalDrawingPublication_drawingId_fkey" FOREIGN KEY ("drawingId")
    REFERENCES "inventory"."ProductTechnicalDrawing"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "ProductTechnicalDrawingPublication_status_check" CHECK ("status" IN ('PREVIEWED', 'SENDING', 'SUBMITTED', 'FAILED'))
);

CREATE INDEX IF NOT EXISTS "ProductTechnicalDrawingPublication_drawingId_createdAt_idx"
  ON "inventory"."ProductTechnicalDrawingPublication"("drawingId", "createdAt");

-- Una sola riga per SKU e paese in ogni pubblicazione: una conferma ripetuta non ne aggiunge.
CREATE UNIQUE INDEX IF NOT EXISTS "ProductTechnicalDrawingPublication_batch_sku_marketplace_key"
  ON "inventory"."ProductTechnicalDrawingPublication"("batchId", "skuCode", "marketplaceId");

COMMENT ON TABLE "inventory"."ProductTechnicalDrawing" IS
  'Disegni tecnici quotati del prodotto, calcolati dal 3MF: file, scelte fatte e 3MF di origine.';
COMMENT ON COLUMN "inventory"."ProductTechnicalDrawing"."treemfUrl" IS
  'Product.treemfUrl quando il disegno è stato creato: se è diverso da quello attuale, il 3MF è cambiato.';
COMMENT ON TABLE "inventory"."ProductTechnicalDrawingPublication" IS
  'Invii di un disegno tecnico come foto dell''inserzione Amazon, uno per SKU e paese.';

-- Come le altre tabelle inventory: niente accesso da API, le app usano postgres/service_role.
ALTER TABLE "inventory"."ProductTechnicalDrawing" ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON "inventory"."ProductTechnicalDrawing" FROM anon, authenticated;
ALTER TABLE "inventory"."ProductTechnicalDrawingPublication" ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON "inventory"."ProductTechnicalDrawingPublication" FROM anon, authenticated;
