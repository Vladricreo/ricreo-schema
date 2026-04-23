-- Aggiunge il valore enum per memorizzare il token API ZonWizard cifrato in inventory.Settings.
ALTER TYPE "inventory"."SettingsName" ADD VALUE IF NOT EXISTS 'ZONWIZARD_API_CREDENTIALS';
