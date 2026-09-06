-- Corrieri Sendcloud predefiniti per paese (codici presi da GET /contracts).
ALTER TYPE "inventory"."SettingsName" ADD VALUE IF NOT EXISTS 'SENDCLOUD_DEFAULT_CARRIERS_BY_COUNTRY';
