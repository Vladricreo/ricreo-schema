-- Lotto fornitore generato internamente (R-248, 16/11/2026).
-- I lotti d'acquisto senza un lotto fornitore vero (vuoto, o copiato dal codice
-- del lotto interno) ricevono CODICE-AAAAMMGG-INT:
--   CODICE = codice articolo (parti: nome normalizzato), max 24 caratteri
--   data   = data d'acquisto: riga d'ordine, poi ordine, poi ricezione, poi
--            creazione del lotto (ora di Roma)
-- Più lotti con lo stesso codice per lo stesso articolo/parte: -2, -3, …
-- Il codice del lotto interno (`code`) non cambia. Idempotente: tocca solo i
-- lotti con lotto fornitore vuoto o uguale al codice interno.

WITH src AS (
  SELECT l.id,
         l."itemId",
         l."productPartId",
         left(
           regexp_replace(
             regexp_replace(upper(COALESCE(i.sku, pp.name, 'ART')), '[^A-Z0-9]+', '-', 'g'),
             '^-+|-+$', '', 'g'),
           24) AS code_part,
         to_char(
           (COALESCE(pol."orderedAt", po."orderedAt", l."receivedAt", l."createdAt") AT TIME ZONE 'Europe/Rome'),
           'YYYYMMDD') AS ymd,
         l."createdAt"
    FROM "inventory"."InventoryLot" l
    LEFT JOIN "inventory"."Item" i ON i.id = l."itemId"
    LEFT JOIN "inventory"."ProductPart" pp ON pp.id = l."productPartId"
    LEFT JOIN "inventory"."PurchaseOrderLine" pol ON pol.id = l."purchaseOrderLineId"
    LEFT JOIN "inventory"."PurchaseOrder" po ON po.id = pol."orderId"
   WHERE l."originType" = 'PURCHASE'
     AND (l."supplierLotCode" IS NULL OR l."supplierLotCode" = l.code)
),
named AS (
  SELECT id,
         regexp_replace(code_part, '-+$', '') || '-' || ymd || '-INT' AS base,
         row_number() OVER (
           PARTITION BY COALESCE("itemId", "productPartId"), code_part, ymd
           ORDER BY "createdAt", id
         ) AS n
    FROM src
)
UPDATE "inventory"."InventoryLot" l
   SET "supplierLotCode" = CASE WHEN named.n = 1 THEN named.base ELSE named.base || '-' || named.n END
  FROM named
 WHERE named.id = l.id;
