-- Controllo qualità in assemblaggio (26/11/2026).
-- Spec: docs/superpowers/specs/2026-11-25-controllo-qualita-assemblaggio-design.md
--
-- Solo tabelle nuove e un trigger: nessuna colonna nuova su tabelle esistenti, nessun valore
-- nuovo in enum esistenti (SettingsName, LotInspectionSource). Interruttore generale SPENTO:
-- finché resta spento nessun blocco e nessuna chiamata. Ripetibile.
--
-- Contenuto:
--   * 4 enum e 14 tabelle del controllo qualità, con RLS attiva;
--   * due indici univoci parziali, non esprimibili nel modello Prisma:
--       - un solo controllo aperto per ordine (CALLING, WAITING, IN_PROGRESS, REWORK);
--       - una sola odetta parcheggiata attiva (releasedAt nullo);
--   * trigger su AssemblyOrder: QualityOrderState.peakTarget = massimo di quantityToAssemble
--     visto dall'ordine, così ridurre l'ordine non fa sfuggire alla soglia;
--   * riga impostazioni (id = 1) coi valori base, 11 voci rapide it/en/bn, catena di chiamata
--     Adriana, Vlad, Davide (ultima risorsa) cercati per username.
--
-- Va applicata prima del deploy del client che la legge. I vincoli verso AssemblyOrder, Odette,
-- InventoryLot, Product, User e Role chiedono un lock su tabelle molto usate: se non arriva
-- meglio fallire subito e rilanciare che accodare dietro tutto il resto.

SET lock_timeout = '10s';

-- ---------------------------------------------------------------------------
-- Enum
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
                 WHERE n.nspname = 'inventory' AND t.typname = 'QualityCheckReason') THEN
    CREATE TYPE "inventory"."QualityCheckReason" AS ENUM ('LARGE_ORDER', 'COUNTER', 'ON_REQUEST');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
                 WHERE n.nspname = 'inventory' AND t.typname = 'QualityCheckStatus') THEN
    CREATE TYPE "inventory"."QualityCheckStatus" AS ENUM
      ('CALLING', 'WAITING', 'IN_PROGRESS', 'REWORK', 'APPROVED', 'SKIPPED', 'UNLOCKED', 'NOT_DONE');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
                 WHERE n.nspname = 'inventory' AND t.typname = 'QualityCallAnswer') THEN
    CREATE TYPE "inventory"."QualityCallAnswer" AS ENUM ('COMING', 'CANNOT', 'ABSENT', 'TIMEOUT');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
                 WHERE n.nspname = 'inventory' AND t.typname = 'QualityIssueStatus') THEN
    CREATE TYPE "inventory"."QualityIssueStatus" AS ENUM ('OPEN', 'RESOLVED');
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Tabelle
-- ---------------------------------------------------------------------------

-- Impostazioni: una sola riga (id = 1). Fuori da SettingsName di proposito.
CREATE TABLE IF NOT EXISTS "inventory"."QualityControlSettings" (
  "id"                  INTEGER        NOT NULL DEFAULT 1,
  "enabled"             BOOLEAN        NOT NULL DEFAULT false,
  "enabledSince"        TIMESTAMPTZ(6),
  "thresholdFba"        INTEGER        NOT NULL DEFAULT 50,
  "thresholdFbm"        INTEGER        NOT NULL DEFAULT 50,
  "thresholdOther"      INTEGER        NOT NULL DEFAULT 50,
  "smallOrderPieces"    INTEGER        NOT NULL DEFAULT 100,
  "smallOrderJitterPct" INTEGER        NOT NULL DEFAULT 30,
  "freeRemainder"       INTEGER        NOT NULL DEFAULT 0,
  "answerSeconds"       INTEGER        NOT NULL DEFAULT 120,
  "arrivalMinutes"      INTEGER        NOT NULL DEFAULT 15,
  "preAlertEnabled"     BOOLEAN        NOT NULL DEFAULT true,
  "preAlertPct"         INTEGER        NOT NULL DEFAULT 80,
  "soundEnabled"        BOOLEAN        NOT NULL DEFAULT true,
  "sampleTable"         JSONB          NOT NULL DEFAULT '[{"max":15,"n":2},{"max":25,"n":3},{"max":90,"n":5},{"max":150,"n":8},{"max":280,"n":13},{"max":500,"n":20},{"max":null,"n":32}]'::jsonb,
  "updatedByUserId"     INTEGER,
  "updatedAt"           TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "QualityControlSettings_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "QualityControlSettings_single_row_check" CHECK ("id" = 1),
  CONSTRAINT "QualityControlSettings_updatedByUserId_fkey" FOREIGN KEY ("updatedByUserId")
    REFERENCES "public"."User"("id") ON DELETE SET NULL ON UPDATE CASCADE
);
CREATE INDEX IF NOT EXISTS "QualityControlSettings_updatedByUserId_idx"
  ON "inventory"."QualityControlSettings"("updatedByUserId");

-- Ruoli che firmano i controlli.
CREATE TABLE IF NOT EXISTS "inventory"."QualityRole" (
  "roleId"    UUID           NOT NULL,
  "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "QualityRole_pkey" PRIMARY KEY ("roleId"),
  CONSTRAINT "QualityRole_roleId_fkey" FOREIGN KEY ("roleId")
    REFERENCES "public"."Role"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- Picco del bersaglio per ordine di assemblaggio (lo tiene il trigger più sotto).
CREATE TABLE IF NOT EXISTS "inventory"."QualityOrderState" (
  "assemblyOrderId" UUID           NOT NULL,
  "peakTarget"      INTEGER        NOT NULL DEFAULT 0,
  "preAlertSentAt"  TIMESTAMPTZ(6),
  "updatedAt"       TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "QualityOrderState_pkey" PRIMARY KEY ("assemblyOrderId"),
  CONSTRAINT "QualityOrderState_assemblyOrderId_fkey" FOREIGN KEY ("assemblyOrderId")
    REFERENCES "inventory"."AssemblyOrder"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- Catena di chiamata.
CREATE TABLE IF NOT EXISTS "inventory"."QualityCallMember" (
  "id"           UUID           NOT NULL DEFAULT gen_random_uuid(),
  "userId"       INTEGER        NOT NULL,
  "position"     INTEGER        NOT NULL,
  "isLastResort" BOOLEAN        NOT NULL DEFAULT false,
  "createdAt"    TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "QualityCallMember_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "QualityCallMember_userId_fkey" FOREIGN KEY ("userId")
    REFERENCES "public"."User"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE UNIQUE INDEX IF NOT EXISTS "QualityCallMember_userId_key"
  ON "inventory"."QualityCallMember"("userId");
CREATE INDEX IF NOT EXISTS "QualityCallMember_position_idx"
  ON "inventory"."QualityCallMember"("position");

-- Controlli.
CREATE TABLE IF NOT EXISTS "inventory"."QualityCheck" (
  "id"                 UUID                             NOT NULL DEFAULT gen_random_uuid(),
  "assemblyOrderId"    UUID                             NOT NULL,
  "stageType"          "inventory"."AssemblyStageType"  NOT NULL,
  "reason"             "inventory"."QualityCheckReason" NOT NULL,
  "status"             "inventory"."QualityCheckStatus" NOT NULL DEFAULT 'CALLING',
  "round"              INTEGER                          NOT NULL DEFAULT 1,
  "coveredQuantity"    INTEGER                          NOT NULL DEFAULT 0,
  "approvedQuantity"   INTEGER                          NOT NULL DEFAULT 0,
  "scrappedQuantity"   INTEGER                          NOT NULL DEFAULT 0,
  "carriedQuantity"    INTEGER                          NOT NULL DEFAULT 0,
  "scrapRevertedQuantity" INTEGER                       NOT NULL DEFAULT 0,
  "scrapRevertedAt"    TIMESTAMPTZ(6),
  "scrapRevertedByUserId" INTEGER,
  "samplePlan"         JSONB,
  "operatorsByStage"   JSONB,
  "requestedByUserId"  INTEGER,
  "openedByUserId"     INTEGER,
  "openedAt"           TIMESTAMPTZ(6),
  "signedByUserId"     INTEGER,
  "signedAt"           TIMESTAMPTZ(6),
  "signedAsLastResort" BOOLEAN                          NOT NULL DEFAULT false,
  "confirmedByUserId"  INTEGER,
  "confirmedAt"        TIMESTAMPTZ(6),
  "note"               TEXT,
  "closeReason"        TEXT,
  "counterSnapshot"    JSONB,
  "waitingSeconds"     INTEGER                          NOT NULL DEFAULT 0,
  "createdAt"          TIMESTAMPTZ(6)                   NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt"          TIMESTAMPTZ(6)                   NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "QualityCheck_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "QualityCheck_assemblyOrderId_fkey" FOREIGN KEY ("assemblyOrderId")
    REFERENCES "inventory"."AssemblyOrder"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "QualityCheck_requestedByUserId_fkey" FOREIGN KEY ("requestedByUserId")
    REFERENCES "public"."User"("id") ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT "QualityCheck_openedByUserId_fkey" FOREIGN KEY ("openedByUserId")
    REFERENCES "public"."User"("id") ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT "QualityCheck_signedByUserId_fkey" FOREIGN KEY ("signedByUserId")
    REFERENCES "public"."User"("id") ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT "QualityCheck_confirmedByUserId_fkey" FOREIGN KEY ("confirmedByUserId")
    REFERENCES "public"."User"("id") ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT "QualityCheck_scrapRevertedByUserId_fkey" FOREIGN KEY ("scrapRevertedByUserId")
    REFERENCES "public"."User"("id") ON DELETE SET NULL ON UPDATE CASCADE
);
CREATE INDEX IF NOT EXISTS "QualityCheck_assemblyOrderId_status_idx"
  ON "inventory"."QualityCheck"("assemblyOrderId", "status");
CREATE INDEX IF NOT EXISTS "QualityCheck_status_idx" ON "inventory"."QualityCheck"("status");
CREATE INDEX IF NOT EXISTS "QualityCheck_requestedByUserId_idx" ON "inventory"."QualityCheck"("requestedByUserId");
CREATE INDEX IF NOT EXISTS "QualityCheck_openedByUserId_idx" ON "inventory"."QualityCheck"("openedByUserId");
CREATE INDEX IF NOT EXISTS "QualityCheck_signedByUserId_idx" ON "inventory"."QualityCheck"("signedByUserId");
CREATE INDEX IF NOT EXISTS "QualityCheck_confirmedByUserId_idx" ON "inventory"."QualityCheck"("confirmedByUserId");
CREATE INDEX IF NOT EXISTS "QualityCheck_scrapRevertedByUserId_idx" ON "inventory"."QualityCheck"("scrapRevertedByUserId");

-- Un solo controllo aperto per ordine.
CREATE UNIQUE INDEX IF NOT EXISTS "QualityCheck_order_open_key"
  ON "inventory"."QualityCheck"("assemblyOrderId")
  WHERE "status" IN ('CALLING', 'WAITING', 'IN_PROGRESS', 'REWORK');

-- Chiamate ai responsabili.
CREATE TABLE IF NOT EXISTS "inventory"."QualityCheckCall" (
  "id"               UUID                            NOT NULL DEFAULT gen_random_uuid(),
  "checkId"          UUID                            NOT NULL,
  "userId"           INTEGER                         NOT NULL,
  "round"            INTEGER                         NOT NULL DEFAULT 1,
  "step"             INTEGER                         NOT NULL,
  "calledAt"         TIMESTAMPTZ(6)                  NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "answer"           "inventory"."QualityCallAnswer",
  "answeredAt"       TIMESTAMPTZ(6),
  "answeredByUserId" INTEGER,
  CONSTRAINT "QualityCheckCall_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "QualityCheckCall_checkId_fkey" FOREIGN KEY ("checkId")
    REFERENCES "inventory"."QualityCheck"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "QualityCheckCall_userId_fkey" FOREIGN KEY ("userId")
    REFERENCES "public"."User"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "QualityCheckCall_answeredByUserId_fkey" FOREIGN KEY ("answeredByUserId")
    REFERENCES "public"."User"("id") ON DELETE SET NULL ON UPDATE CASCADE
);
CREATE UNIQUE INDEX IF NOT EXISTS "QualityCheckCall_checkId_round_step_key" ON "inventory"."QualityCheckCall"("checkId", "round", "step");
CREATE INDEX IF NOT EXISTS "QualityCheckCall_checkId_idx" ON "inventory"."QualityCheckCall"("checkId");
CREATE INDEX IF NOT EXISTS "QualityCheckCall_userId_idx" ON "inventory"."QualityCheckCall"("userId");
CREATE INDEX IF NOT EXISTS "QualityCheckCall_answeredByUserId_idx" ON "inventory"."QualityCheckCall"("answeredByUserId");

-- Voci rapide del registro (create prima dei campioni che le citano).
CREATE TABLE IF NOT EXISTS "inventory"."QualityIssueType" (
  "id"        UUID           NOT NULL DEFAULT gen_random_uuid(),
  "key"       TEXT           NOT NULL,
  "labelIt"   TEXT           NOT NULL,
  "labelEn"   TEXT           NOT NULL,
  "labelBn"   TEXT           NOT NULL,
  "sortOrder" INTEGER        NOT NULL DEFAULT 0,
  "isActive"  BOOLEAN        NOT NULL DEFAULT true,
  "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "QualityIssueType_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX IF NOT EXISTS "QualityIssueType_key_key" ON "inventory"."QualityIssueType"("key");
CREATE INDEX IF NOT EXISTS "QualityIssueType_sortOrder_idx" ON "inventory"."QualityIssueType"("sortOrder");

-- Campioni controllati.
CREATE TABLE IF NOT EXISTS "inventory"."QualityCheckSample" (
  "id"          UUID           NOT NULL DEFAULT gen_random_uuid(),
  "checkId"     UUID           NOT NULL,
  "round"       INTEGER        NOT NULL DEFAULT 1,
  "index"       INTEGER        NOT NULL,
  "ok"          BOOLEAN        NOT NULL,
  "issueTypeId" UUID,
  "operatorId"  INTEGER,
  "note"        TEXT,
  "photoUrl"    TEXT,
  "createdAt"   TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "QualityCheckSample_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "QualityCheckSample_checkId_fkey" FOREIGN KEY ("checkId")
    REFERENCES "inventory"."QualityCheck"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "QualityCheckSample_issueTypeId_fkey" FOREIGN KEY ("issueTypeId")
    REFERENCES "inventory"."QualityIssueType"("id") ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT "QualityCheckSample_operatorId_fkey" FOREIGN KEY ("operatorId")
    REFERENCES "public"."User"("id") ON DELETE SET NULL ON UPDATE CASCADE
);
CREATE INDEX IF NOT EXISTS "QualityCheckSample_checkId_round_idx" ON "inventory"."QualityCheckSample"("checkId", "round");
CREATE INDEX IF NOT EXISTS "QualityCheckSample_issueTypeId_idx" ON "inventory"."QualityCheckSample"("issueTypeId");
CREATE INDEX IF NOT EXISTS "QualityCheckSample_operatorId_idx" ON "inventory"."QualityCheckSample"("operatorId");

-- Lotti coperti da un controllo.
CREATE TABLE IF NOT EXISTS "inventory"."QualityCheckLot" (
  "checkId" UUID NOT NULL,
  "lotId"   UUID NOT NULL,
  CONSTRAINT "QualityCheckLot_pkey" PRIMARY KEY ("checkId", "lotId"),
  CONSTRAINT "QualityCheckLot_checkId_fkey" FOREIGN KEY ("checkId")
    REFERENCES "inventory"."QualityCheck"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "QualityCheckLot_lotId_fkey" FOREIGN KEY ("lotId")
    REFERENCES "inventory"."InventoryLot"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX IF NOT EXISTS "QualityCheckLot_lotId_idx" ON "inventory"."QualityCheckLot"("lotId");

-- Registro delle non conformità: le righe sopravvivono a controllo, ordine, lotto e prodotto.
CREATE TABLE IF NOT EXISTS "inventory"."QualityIssue" (
  "id"               UUID                             NOT NULL DEFAULT gen_random_uuid(),
  "issueTypeId"      UUID,
  "checkId"          UUID,
  "sampleId"         UUID,
  "assemblyOrderId"  UUID,
  "stageType"        "inventory"."AssemblyStageType",
  "lotId"            UUID,
  "productId"        UUID,
  "operatorId"       INTEGER,
  "quantity"         INTEGER                          NOT NULL DEFAULT 1,
  "note"             TEXT,
  "photos"           TEXT[]                           NOT NULL DEFAULT ARRAY[]::TEXT[],
  "status"           "inventory"."QualityIssueStatus" NOT NULL DEFAULT 'OPEN',
  "resolution"       TEXT,
  "createdByUserId"  INTEGER,
  "resolvedByUserId" INTEGER,
  "resolvedAt"       TIMESTAMPTZ(6),
  "createdAt"        TIMESTAMPTZ(6)                   NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt"        TIMESTAMPTZ(6)                   NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "QualityIssue_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "QualityIssue_issueTypeId_fkey" FOREIGN KEY ("issueTypeId")
    REFERENCES "inventory"."QualityIssueType"("id") ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT "QualityIssue_checkId_fkey" FOREIGN KEY ("checkId")
    REFERENCES "inventory"."QualityCheck"("id") ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT "QualityIssue_sampleId_fkey" FOREIGN KEY ("sampleId")
    REFERENCES "inventory"."QualityCheckSample"("id") ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT "QualityIssue_assemblyOrderId_fkey" FOREIGN KEY ("assemblyOrderId")
    REFERENCES "inventory"."AssemblyOrder"("id") ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT "QualityIssue_lotId_fkey" FOREIGN KEY ("lotId")
    REFERENCES "inventory"."InventoryLot"("id") ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT "QualityIssue_productId_fkey" FOREIGN KEY ("productId")
    REFERENCES "inventory"."Product"("id") ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT "QualityIssue_operatorId_fkey" FOREIGN KEY ("operatorId")
    REFERENCES "public"."User"("id") ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT "QualityIssue_createdByUserId_fkey" FOREIGN KEY ("createdByUserId")
    REFERENCES "public"."User"("id") ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT "QualityIssue_resolvedByUserId_fkey" FOREIGN KEY ("resolvedByUserId")
    REFERENCES "public"."User"("id") ON DELETE SET NULL ON UPDATE CASCADE
);
CREATE UNIQUE INDEX IF NOT EXISTS "QualityIssue_sampleId_key" ON "inventory"."QualityIssue"("sampleId");
CREATE INDEX IF NOT EXISTS "QualityIssue_issueTypeId_idx" ON "inventory"."QualityIssue"("issueTypeId");
CREATE INDEX IF NOT EXISTS "QualityIssue_checkId_idx" ON "inventory"."QualityIssue"("checkId");
CREATE INDEX IF NOT EXISTS "QualityIssue_assemblyOrderId_idx" ON "inventory"."QualityIssue"("assemblyOrderId");
CREATE INDEX IF NOT EXISTS "QualityIssue_lotId_idx" ON "inventory"."QualityIssue"("lotId");
CREATE INDEX IF NOT EXISTS "QualityIssue_productId_idx" ON "inventory"."QualityIssue"("productId");
CREATE INDEX IF NOT EXISTS "QualityIssue_operatorId_idx" ON "inventory"."QualityIssue"("operatorId");
CREATE INDEX IF NOT EXISTS "QualityIssue_status_createdAt_idx" ON "inventory"."QualityIssue"("status", "createdAt");
CREATE INDEX IF NOT EXISTS "QualityIssue_createdByUserId_idx" ON "inventory"."QualityIssue"("createdByUserId");
CREATE INDEX IF NOT EXISTS "QualityIssue_resolvedByUserId_idx" ON "inventory"."QualityIssue"("resolvedByUserId");

-- Contatore dell'operatore.
CREATE TABLE IF NOT EXISTS "inventory"."QualityOperatorCounter" (
  "userId"    INTEGER        NOT NULL,
  "since"     TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "target"    INTEGER        NOT NULL,
  "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "QualityOperatorCounter_pkey" PRIMARY KEY ("userId"),
  CONSTRAINT "QualityOperatorCounter_userId_fkey" FOREIGN KEY ("userId")
    REFERENCES "public"."User"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- PIN sbagliati al controllo qualità, per persona: il blocco sopravvive ai deploy.
CREATE TABLE IF NOT EXISTS "inventory"."QualityPinLock" (
  "userId"      INTEGER        NOT NULL,
  "failures"    INTEGER        NOT NULL DEFAULT 0,
  "lockedUntil" TIMESTAMPTZ(6),
  "lockouts"    INTEGER        NOT NULL DEFAULT 0,
  "disabledAt"  TIMESTAMPTZ(6),
  "updatedAt"   TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "QualityPinLock_pkey" PRIMARY KEY ("userId"),
  CONSTRAINT "QualityPinLock_userId_fkey" FOREIGN KEY ("userId")
    REFERENCES "public"."User"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- Odette parcheggiate in attesa del controllo.
CREATE TABLE IF NOT EXISTS "inventory"."QualityParkedOdette" (
  "id"              UUID           NOT NULL DEFAULT gen_random_uuid(),
  "odetteId"        UUID           NOT NULL,
  "assemblyOrderId" UUID           NOT NULL,
  "checkId"         UUID           NOT NULL,
  "quantity"        INTEGER        NOT NULL,
  "parkedByUserId"  INTEGER,
  "parkedAt"        TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "releasedAt"      TIMESTAMPTZ(6),
  CONSTRAINT "QualityParkedOdette_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "QualityParkedOdette_odetteId_fkey" FOREIGN KEY ("odetteId")
    REFERENCES "inventory"."Odette"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "QualityParkedOdette_assemblyOrderId_fkey" FOREIGN KEY ("assemblyOrderId")
    REFERENCES "inventory"."AssemblyOrder"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "QualityParkedOdette_checkId_fkey" FOREIGN KEY ("checkId")
    REFERENCES "inventory"."QualityCheck"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "QualityParkedOdette_parkedByUserId_fkey" FOREIGN KEY ("parkedByUserId")
    REFERENCES "public"."User"("id") ON DELETE SET NULL ON UPDATE CASCADE
);
CREATE INDEX IF NOT EXISTS "QualityParkedOdette_odetteId_idx" ON "inventory"."QualityParkedOdette"("odetteId");
CREATE INDEX IF NOT EXISTS "QualityParkedOdette_assemblyOrderId_idx" ON "inventory"."QualityParkedOdette"("assemblyOrderId");
CREATE INDEX IF NOT EXISTS "QualityParkedOdette_checkId_idx" ON "inventory"."QualityParkedOdette"("checkId");
CREATE INDEX IF NOT EXISTS "QualityParkedOdette_parkedByUserId_idx" ON "inventory"."QualityParkedOdette"("parkedByUserId");

-- Una sola odetta parcheggiata attiva alla volta.
CREATE UNIQUE INDEX IF NOT EXISTS "QualityParkedOdette_odette_active_key"
  ON "inventory"."QualityParkedOdette"("odetteId") WHERE "releasedAt" IS NULL;

-- Traduzioni delle note libere.
CREATE TABLE IF NOT EXISTS "inventory"."QualityTextTranslation" (
  "id"         UUID           NOT NULL DEFAULT gen_random_uuid(),
  "sourceHash" TEXT           NOT NULL,
  "language"   TEXT           NOT NULL,
  "text"       TEXT           NOT NULL,
  "createdAt"  TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "QualityTextTranslation_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX IF NOT EXISTS "QualityTextTranslation_sourceHash_language_key"
  ON "inventory"."QualityTextTranslation"("sourceHash", "language");

-- ---------------------------------------------------------------------------
-- RLS: come le altre tabelle inventory, niente accesso da API; le app usano postgres/service_role.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'QualityControlSettings', 'QualityRole', 'QualityOrderState', 'QualityCallMember',
    'QualityCheck', 'QualityCheckCall', 'QualityIssueType', 'QualityCheckSample',
    'QualityCheckLot', 'QualityIssue', 'QualityOperatorCounter', 'QualityParkedOdette',
    'QualityTextTranslation', 'QualityPinLock'
  ] LOOP
    EXECUTE format('ALTER TABLE "inventory".%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('REVOKE ALL ON "inventory".%I FROM anon, authenticated', t);
  END LOOP;
END $$;

COMMENT ON TABLE "inventory"."QualityControlSettings" IS
  'Impostazioni del controllo qualità in assemblaggio: una sola riga (id = 1). Interruttore spento di base.';
COMMENT ON TABLE "inventory"."QualityRole" IS
  'Ruoli che firmano i controlli qualità; essere Admin o Manager non basta.';
COMMENT ON TABLE "inventory"."QualityOrderState" IS
  'Picco di quantityToAssemble visto da ogni ordine di assemblaggio (trigger), per non sfuggire alla soglia riducendo l''ordine.';
COMMENT ON TABLE "inventory"."QualityCallMember" IS
  'Catena di chiamata dei responsabili qualità; isLastResort firma anche senza ruolo.';
COMMENT ON TABLE "inventory"."QualityCheck" IS
  'Controllo qualità di un ordine di assemblaggio in una fase; un solo controllo aperto per ordine.';
COMMENT ON TABLE "inventory"."QualityCheckCall" IS
  'Chiamate ai responsabili per un controllo e relative risposte.';
COMMENT ON TABLE "inventory"."QualityCheckSample" IS
  'Campioni controllati in ogni giro di un controllo.';
COMMENT ON TABLE "inventory"."QualityCheckLot" IS
  'Lotti coperti da un controllo.';
COMMENT ON TABLE "inventory"."QualityIssueType" IS
  'Voci rapide del registro delle non conformità, con etichette it/en/bn.';
COMMENT ON TABLE "inventory"."QualityIssue" IS
  'Registro delle non conformità: una riga per fatto, da controlli o segnalazioni a mano.';
COMMENT ON TABLE "inventory"."QualityOperatorCounter" IS
  'Contatore dei pezzi assemblati dall''operatore dall''ultimo controllo e bersaglio che fa scattare il successivo.';
COMMENT ON TABLE "inventory"."QualityPinLock" IS
  'PIN sbagliati al controllo qualità per persona: 5 di fila bloccano 15 minuti, al terzo blocco il PIN non vale più finché la persona non apre un controllo dal suo account.';
COMMENT ON TABLE "inventory"."QualityParkedOdette" IS
  'Odette parcheggiate in attesa del controllo; una sola attiva per odetta.';
COMMENT ON TABLE "inventory"."QualityTextTranslation" IS
  'Traduzioni delle note libere dall''italiano, per hash del testo e lingua.';

-- ---------------------------------------------------------------------------
-- Trigger: picco di quantityToAssemble
--
-- Solo upsert su QualityOrderState, e solo se il valore sale. SECURITY DEFINER: la funzione gira
-- coi diritti del proprietario, così un ruolo che scrive gli ordini senza BYPASSRLS né permessi
-- su QualityOrderState non fa mai fallire un INSERT o UPDATE di AssemblyOrder. Per questo
-- search_path è vuoto e i nomi sono qualificati; l'esecuzione diretta è tolta a tutti.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "inventory".quality_order_peak_target_trg()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO "inventory"."QualityOrderState" ("assemblyOrderId", "peakTarget")
  VALUES (NEW."id", GREATEST(COALESCE(NEW."quantityToAssemble", 0), 0))
  ON CONFLICT ("assemblyOrderId") DO UPDATE
    SET "peakTarget" = EXCLUDED."peakTarget",
        "updatedAt"  = CURRENT_TIMESTAMP
    WHERE "QualityOrderState"."peakTarget" < EXCLUDED."peakTarget";
  RETURN NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION "inventory".quality_order_peak_target_trg() FROM PUBLIC, anon, authenticated;

-- Due trigger: all'inserimento sempre, in modifica solo se la quantità cambia davvero.
DROP TRIGGER IF EXISTS "AssemblyOrder_quality_peak_target" ON "inventory"."AssemblyOrder";
DROP TRIGGER IF EXISTS "AssemblyOrder_quality_peak_target_ins" ON "inventory"."AssemblyOrder";
DROP TRIGGER IF EXISTS "AssemblyOrder_quality_peak_target_upd" ON "inventory"."AssemblyOrder";
CREATE TRIGGER "AssemblyOrder_quality_peak_target_ins"
AFTER INSERT
ON "inventory"."AssemblyOrder"
FOR EACH ROW
EXECUTE FUNCTION "inventory".quality_order_peak_target_trg();
CREATE TRIGGER "AssemblyOrder_quality_peak_target_upd"
AFTER UPDATE OF "quantityToAssemble"
ON "inventory"."AssemblyOrder"
FOR EACH ROW
WHEN (NEW."quantityToAssemble" IS DISTINCT FROM OLD."quantityToAssemble")
EXECUTE FUNCTION "inventory".quality_order_peak_target_trg();

-- Ordini già in corso: il picco parte dalla quantità di adesso.
INSERT INTO "inventory"."QualityOrderState" ("assemblyOrderId", "peakTarget")
SELECT ao."id", GREATEST(ao."quantityToAssemble", 0)
FROM "inventory"."AssemblyOrder" ao
WHERE ao."status" NOT IN ('ASSEMBLY_COMPLETED', 'CANCELLED')
ON CONFLICT ("assemblyOrderId") DO UPDATE
  SET "peakTarget" = GREATEST("QualityOrderState"."peakTarget", EXCLUDED."peakTarget"),
      "updatedAt"  = CURRENT_TIMESTAMP;

-- ---------------------------------------------------------------------------
-- Dati iniziali
-- ---------------------------------------------------------------------------

-- Impostazioni coi valori base: interruttore spento.
INSERT INTO "inventory"."QualityControlSettings" ("id") VALUES (1) ON CONFLICT ("id") DO NOTHING;

-- Voci rapide di partenza (modificabili in Impostazioni).
INSERT INTO "inventory"."QualityIssueType" ("key", "labelIt", "labelEn", "labelBn", "sortOrder") VALUES
  ('kits_not_inserted',       'Corredi non inseriti',                         'Kit items not inserted',                 'কিটের সামগ্রী ঢোকানো হয়নি',        10),
  ('print_quality_unchecked', 'Qualità dei pezzi stampati non controllata',   'Print quality of the parts not checked', 'ছাপা অংশের মান যাচাই করা হয়নি',     20),
  ('assembly_incomplete',     'Montaggio incompleto o sbagliato',             'Incomplete or wrong assembly',           'সংযোজন অসম্পূর্ণ বা ভুল',           30),
  ('screws_magnets_missing',  'Viti o magneti mancanti',                      'Missing screws or magnets',              'স্ক্রু বা চুম্বক নেই',              40),
  ('dirty_or_stress_marks',   'Pezzo sporco o con stress mark',               'Dirty part or with stress marks',        'অংশ নোংরা বা স্ট্রেস মার্ক আছে',    50),
  ('color_mismatch',          'Colore diverso fra le parti',                  'Different colour between parts',         'অংশগুলোর মধ্যে রঙের পার্থক্য',       60),
  ('label_wrong_or_missing',  'Etichetta sbagliata o mancante',               'Wrong or missing label',                 'লেবেল ভুল বা নেই',                  70),
  ('qr_guide_missing',        'Guida QR mancante',                            'QR guide missing',                       'QR গাইড নেই',                       80),
  ('bag_quantity_wrong',      'Quantità sbagliata nella busta',               'Wrong quantity in the bag',              'ব্যাগে পরিমাণ ভুল',                 90),
  ('bag_wrong_or_torn',       'Busta sbagliata o rotta',                      'Wrong or torn bag',                      'ব্যাগ ভুল বা ছেঁড়া',                100),
  ('other',                   'Altro',                                        'Other',                                  'অন্যান্য',                          110)
ON CONFLICT ("key") DO NOTHING;

-- Catena di chiamata: Adriana, Vlad, Davide (ultima risorsa), cercati per username
-- (senza distinguere maiuscole). Uno username mancante non inserisce nulla.
INSERT INTO "inventory"."QualityCallMember" ("userId", "position", "isLastResort")
SELECT u."id", v."position", v."isLastResort"
FROM (VALUES
  ('adriana', 1, false),
  ('vlad',    2, false),
  ('davide',  3, true)
) AS v("username", "position", "isLastResort")
JOIN "public"."User" u ON lower(u."username") = v."username"
ON CONFLICT ("userId") DO NOTHING;
