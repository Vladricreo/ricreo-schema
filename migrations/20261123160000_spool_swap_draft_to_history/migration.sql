-- Storico della bobina A delle bozze swap/runout (23/11, diagnosi del
-- ping-pong delle bobine sulle stampanti congelate). Colonna nullable: nessun
-- effetto sulle righe esistenti.
ALTER TABLE "print-farm"."SpoolSwapDraft"
    ADD COLUMN "toHistory" JSONB;
