-- Aggiunge i permessi di menu per "Ordini > Consumi" (nuova pagina) e
-- "Gestione utility" (già presente in src/constants/data.ts e prisma/seed.ts,
-- ma mai inserito tramite migration: se il seed non è stato rieseguito dopo
-- l'introduzione della voce, il permesso risulta assente in produzione).
--
-- Concede il permesso "view" ai ruoli Admin e Manager, coerentemente con la
-- logica di prisma/seed.ts (Admin = tutti i permessi, Manager = tutti tranne
-- "users").

INSERT INTO "public"."Permission" ("id", "name", "resource", "action", "description", "createdAt", "updatedAt")
VALUES
  (gen_random_uuid(), 'orders-consumptions:view', 'orders-consumptions', 'view', 'Visualizza Consumi', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  (gen_random_uuid(), 'utilities-manager:view', 'utilities-manager', 'view', 'Visualizza Utilities Manager', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
ON CONFLICT ("resource", "action") DO NOTHING;

INSERT INTO "public"."RolePermission" ("roleId", "permissionId")
SELECT r."id", p."id"
FROM "public"."Role" r
CROSS JOIN "public"."Permission" p
WHERE r."name" IN ('Admin', 'Manager')
  AND p."resource" IN ('orders-consumptions', 'utilities-manager')
  AND p."action" = 'view'
ON CONFLICT ("roleId", "permissionId") DO NOTHING;
