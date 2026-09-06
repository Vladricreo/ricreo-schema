-- Aggiunge il valore enum per memorizzare l'indirizzo mittente FBA inbound in inventory.Settings.
ALTER TYPE "inventory"."SettingsName" ADD VALUE IF NOT EXISTS 'FBA_INBOUND_SOURCE_ADDRESS';
