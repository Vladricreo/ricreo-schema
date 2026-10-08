-- ============================================================================
-- Scaffali: misure dei ripiani, larghezza e capienza delle sezioni,
-- sezione dedicata a uno SKU (decisione utente 2026-10-08, pagina
-- Inventory /storage/shelfs).
--
-- Perché: calcolare quanti pacchi di prodotto finito stanno in una sezione
-- (larghezza occupata × profondità × altezza del ripiano ÷ misure pacco
-- `Sku.dimensions`, in mm) oppure inserirlo a mano, e suggerire di allargare
-- o ridurre la sezione in base alla velocità di vendita.
--
-- - WarehouseShelf.tier{Width,Depth,Height}Mm: misure standard dei ripiani
--   (di base i ripiani di uno scaffale sono uguali).
-- - WarehouseRow.{width,depth,height}Mm: override per il singolo ripiano.
-- - WarehouseLocation.widthMm: larghezza del ripiano occupata dalla sezione.
-- - WarehouseLocation.manualCapacity: capienza in pezzi inserita a mano,
--   prevale sul calcolo.
-- - WarehouseLocation.dedicatedSkuId: SKU a cui la sezione è dedicata anche
--   quando è vuota. Il selettore posizione dell'assemblaggio (Inventory)
--   propone la sezione dedicata e non la offre ad altri SKU.
--
-- Nessun dato toccato: tutte le colonne sono nullable, senza default.
-- Sku.maxStock NON viene scritto da questa migrazione né in automatico:
-- il "max suggerito" si applica solo a mano, SKU per SKU, dalla pagina.
--
-- !! DEPLOY: applicare PRIMA del deploy di Inventory e PF !!
-- Il client Prisma rigenerato legge le colonne in ogni query su
-- "WarehouseShelf" / "WarehouseRow" / "WarehouseLocation" senza select
-- esplicita: senza le colonne quelle query falliscono. Applicarla prima è
-- innocuo (il codice vecchio non le conosce).
--
-- Idempotente: ADD COLUMN IF NOT EXISTS, CREATE INDEX IF NOT EXISTS, FK
-- creata solo se assente.
-- Applicabile anche via psql / Supabase SQL editor; in quel caso:
--   bunx prisma migrate resolve --applied 20261008100000_shelf_dimensions_capacity
-- ============================================================================

ALTER TABLE "inventory"."WarehouseShelf"
  ADD COLUMN IF NOT EXISTS "tierWidthMm" INTEGER,
  ADD COLUMN IF NOT EXISTS "tierDepthMm" INTEGER,
  ADD COLUMN IF NOT EXISTS "tierHeightMm" INTEGER;

ALTER TABLE "inventory"."WarehouseRow"
  ADD COLUMN IF NOT EXISTS "widthMm" INTEGER,
  ADD COLUMN IF NOT EXISTS "depthMm" INTEGER,
  ADD COLUMN IF NOT EXISTS "heightMm" INTEGER;

ALTER TABLE "inventory"."WarehouseLocation"
  ADD COLUMN IF NOT EXISTS "widthMm" INTEGER,
  ADD COLUMN IF NOT EXISTS "manualCapacity" INTEGER,
  ADD COLUMN IF NOT EXISTS "dedicatedSkuId" UUID;

CREATE INDEX IF NOT EXISTS "WarehouseLocation_dedicatedSkuId_idx"
  ON "inventory"."WarehouseLocation"("dedicatedSkuId");

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'WarehouseLocation_dedicatedSkuId_fkey'
  ) THEN
    ALTER TABLE "inventory"."WarehouseLocation"
      ADD CONSTRAINT "WarehouseLocation_dedicatedSkuId_fkey"
      FOREIGN KEY ("dedicatedSkuId") REFERENCES "inventory"."Sku"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;

COMMENT ON COLUMN "inventory"."WarehouseShelf"."tierWidthMm" IS
  'Larghezza utile standard dei ripiani (mm): lato su cui si affiancano le sezioni.';
COMMENT ON COLUMN "inventory"."WarehouseShelf"."tierDepthMm" IS
  'Profondità utile standard dei ripiani (mm).';
COMMENT ON COLUMN "inventory"."WarehouseShelf"."tierHeightMm" IS
  'Altezza utile standard dei ripiani (mm): spazio libero fino al ripiano sopra.';
COMMENT ON COLUMN "inventory"."WarehouseRow"."widthMm" IS
  'Override larghezza utile del ripiano (mm). Null = standard dello scaffale.';
COMMENT ON COLUMN "inventory"."WarehouseRow"."depthMm" IS
  'Override profondità utile del ripiano (mm). Null = standard dello scaffale.';
COMMENT ON COLUMN "inventory"."WarehouseRow"."heightMm" IS
  'Override altezza utile del ripiano (mm). Null = standard dello scaffale.';
COMMENT ON COLUMN "inventory"."WarehouseLocation"."widthMm" IS
  'Larghezza del ripiano occupata dalla sezione (mm), per il calcolo capienza.';
COMMENT ON COLUMN "inventory"."WarehouseLocation"."manualCapacity" IS
  'Capienza della sezione in pezzi inserita a mano; prevale sul calcolo da misure.';
COMMENT ON COLUMN "inventory"."WarehouseLocation"."dedicatedSkuId" IS
  'SKU a cui la sezione è dedicata anche quando è vuota (capienza e selettore posizione assemblaggio).';
