-- ============================================================================
-- F6 fase costi — resolver ItemSpec -> Item "stock-aware" (audit 2026-09-03:
-- PIANO-AZIONE ondata 6 item 5 "breakdown costi"; F6-RECON sezione M4).
--
-- Cosa cambia:
--   * `inventory_views.v_item_spec_resolved`: la variante risolta segue quella
--     che VERREBBE USATA ORA, non solo la preferita da catalogo:
--       1) override attivo (ItemSpecOverride) — invariato, vince sempre;
--       2) altrimenti la variante IN STOCK con `specPriority` piu' bassa
--          (in stock = unita' sigillate `Item.inStock > 0` OPPURE bobina
--          aperta `FilamentSpool` ACTIVE con `remainingWeight > 0` — stesse
--          definizioni di `v_item_open_spool_grams` /
--          `v_item_spec_stock_position`);
--       3) altrimenti la variante preferita per `specPriority` (comportamento
--          precedente: fallback di stabilita' per il pricing quando tutta la
--          famiglia e' esaurita).
--
-- Perche':
--   * Dopo F6 fase 2 lo scheduler matcha spec-first (override promosso, poi
--     varianti con bobine aperte, poi `specPriority`): il costo deve prezzare
--     la stessa variante che la farm monterebbe, non una variante preferita
--     ma esaurita. Evidenza live (2026-09-04): spec "TPU NERO" risolta su
--     "Filamento tpu nero" (8.16 EUR, 0 sigillate + 0 g aperti) mentre la
--     variante realmente usabile e' "Elegoo tpu" (17.00 EUR, 3 sigillate +
--     847 g aperti).
--   * Il tie-break "bobine aperte prima delle sigillate" dello scheduler
--     (drain-first, latched per gruppo) NON e' replicato: aprire/chiudere una
--     bobina farebbe oscillare i prezzi dei consumer (v_sku_pricing_summary,
--     ZonWizard). "In stock" aggregato + specPriority e' il proxy stabile.
--
-- Impatto misurato prima del deploy (query read-only sul DB live):
--   119 spec risolte: 100 invariate (preferita in stock), 18 invariate
--   (famiglia esaurita -> fallback), 1 cambia (TPU NERO), 0 override attivi.
--
-- Solo CREATE OR REPLACE: elenco colonne IDENTICO (spec_id, item_id) — le
-- view dipendenti (v_product_cost_breakdown, v_sku_cost_breakdown,
-- v_sku_pricing_summary, v_product_order_required_items,
-- v_item_spec_stock_position, v_item_*_consumption_demand) restano valide,
-- nessun DROP. Idempotente per definizione (OR REPLACE).
--
-- NOTA sincronizzazione: la copia "reference" del resolver in
-- Ricreo-Inventory `client/prisma/custom_migrations/sql/stock_views_and_triggers.sql`
-- (sezione 1.11.1) e' allineata a questa migrazione: una riapplicazione
-- manuale di quel file NON deve regredire questa logica.
--
-- Applicabile anche via psql / Supabase SQL editor. Se lo fai fuori da Prisma:
--   bunx prisma migrate resolve --applied 20260904043000_item_spec_resolved_stock_aware
-- ============================================================================

CREATE OR REPLACE VIEW inventory_views.v_item_spec_resolved AS
SELECT
  s.id AS spec_id,
  COALESCE(ov.item_id, st.item_id, it.item_id) AS item_id
FROM inventory."ItemSpec" s
-- 1) Override attivo (sostituzione approvata operatore): vince sempre.
LEFT JOIN LATERAL (
  SELECT o."itemId" AS item_id
  FROM inventory."ItemSpecOverride" o
  WHERE o."specId" = s.id
    AND o."isActive" = true
    AND o."startsAt" <= now()
    AND (o."endsAt" IS NULL OR o."endsAt" > now())
  ORDER BY o."startsAt" DESC
  LIMIT 1
) ov ON true
-- 2) Variante in stock (sigillate O bobine aperte) con specPriority piu' bassa:
--    e' la variante che lo scheduler F6 monterebbe ora.
LEFT JOIN LATERAL (
  SELECT i.id AS item_id
  FROM inventory."Item" i
  WHERE i."itemSpecId" = s.id
    AND (
      COALESCE(i."inStock", 0) > 0
      OR EXISTS (
        SELECT 1
        FROM "print-farm"."FilamentSpool" fs
        WHERE fs."itemId" = i.id
          AND fs.status = 'ACTIVE'
          AND fs."remainingWeight" > 0
      )
    )
  ORDER BY i."specPriority" ASC, i.name ASC, i.id ASC
  LIMIT 1
) st ON true
-- 3) Fallback: preferita per specPriority (stabilita' pricing a stock zero).
LEFT JOIN LATERAL (
  SELECT i.id AS item_id
  FROM inventory."Item" i
  WHERE i."itemSpecId" = s.id
  ORDER BY i."specPriority" ASC, i.name ASC, i.id ASC
  LIMIT 1
) it ON true;
