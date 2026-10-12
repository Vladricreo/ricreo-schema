-- Heartbeat della telemetria fuori da "Printer" (S-119, 12/10).
-- "Printer" è nella pubblicazione supabase_realtime: gli UPDATE di solo
-- heartbeat (~80/min) diventavano eventi Realtime per ogni scheda aperta.
-- Le colonne Printer.lastMqttAt/lastWssAt restano (deprecate) per il codice
-- ancora in esecuzione durante il deploy; si eliminano in una migrazione successiva.

CREATE TABLE "print-farm"."PrinterHeartbeat" (
    "printerId" UUID NOT NULL,
    "lastMqttAt" TIMESTAMPTZ(6),
    "lastWssAt" TIMESTAMPTZ(6),

    CONSTRAINT "PrinterHeartbeat_pkey" PRIMARY KEY ("printerId")
);

ALTER TABLE "print-farm"."PrinterHeartbeat"
    ADD CONSTRAINT "PrinterHeartbeat_printerId_fkey"
    FOREIGN KEY ("printerId") REFERENCES "print-farm"."Printer"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;

INSERT INTO "print-farm"."PrinterHeartbeat" ("printerId", "lastMqttAt", "lastWssAt")
SELECT "id", "lastMqttAt", "lastWssAt"
FROM "print-farm"."Printer"
WHERE "lastMqttAt" IS NOT NULL OR "lastWssAt" IS NOT NULL;
