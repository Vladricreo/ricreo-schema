-- Scorta di sicurezza FBA e SKU iscritti a Pan-EU (29/10/2026).
-- Dopo questa migration ri-eseguire prisma/custom_migrations/sql/fba_inventory_view.sql.

-- Giorni di scorta di sicurezza FBA (default applicativo 14).
ALTER TYPE "inventory"."SettingsName" ADD VALUE IF NOT EXISTS 'AMAZON_SAFETY_STOCK_DAYS';

-- SKU FBA iscritto a Pan-EU: tariffa Amazon per stock basso sotto 28 giorni.
ALTER TABLE "inventory"."Sku" ADD COLUMN IF NOT EXISTS "amazonPanEu" BOOLEAN NOT NULL DEFAULT false;

-- Tariffe di stoccaggio Amazon UE dal rate card 1/2/2026 (standard, non abbigliamento,
-- €/m³/mese): 27,54 gen-set e 52,20 ott-dic. Solo se sono ancora i vecchi 26/36.
UPDATE "inventory"."Settings" SET "value" = '27.54'::jsonb, "updatedAt" = now()
WHERE "name" = 'AMAZON_STORAGE_FEE_LOW' AND ("value" #>> '{}')::numeric = 26;
UPDATE "inventory"."Settings" SET "value" = '52.2'::jsonb, "updatedAt" = now()
WHERE "name" = 'AMAZON_STORAGE_FEE_HIGH' AND ("value" #>> '{}')::numeric = 36;
