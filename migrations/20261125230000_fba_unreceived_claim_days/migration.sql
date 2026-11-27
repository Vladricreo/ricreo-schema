-- Soglia impostabile per le spedizioni FBA mai ricevute (25/11/2026).
-- Default applicativo 45 giorni: nessuna riga da inserire.
ALTER TYPE "inventory"."SettingsName" ADD VALUE IF NOT EXISTS 'AMAZON_UNRECEIVED_SHIPMENT_CLAIM_DAYS';
