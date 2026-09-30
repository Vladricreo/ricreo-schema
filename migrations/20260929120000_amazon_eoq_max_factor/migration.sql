-- Tetto del lotto FBA come multiplo dell'EOQ (usato da v_fba_inventory e dal cron metriche).
-- Dopo questa migration ri-eseguire prisma/custom_migrations/sql/fba_inventory_view.sql.
ALTER TYPE "inventory"."SettingsName" ADD VALUE IF NOT EXISTS 'AMAZON_EOQ_MAX_FACTOR';
