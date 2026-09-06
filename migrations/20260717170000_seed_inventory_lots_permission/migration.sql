-- Aggiunge il permesso di menu per "Inventario > Lotti" (tracciabilità ISO 9001).
-- Concede view ad Admin, Manager e Operatore (coerente con seed/role-templates).

INSERT INTO "public"."Permission" ("id", "name", "resource", "action", "description", "createdAt", "updatedAt")
VALUES
  (gen_random_uuid(), 'inventory-lots:view', 'inventory-lots', 'view', 'Visualizza Tracciabilità Lotti', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
ON CONFLICT ("resource", "action") DO NOTHING;

INSERT INTO "public"."RolePermission" ("roleId", "permissionId")
SELECT r."id", p."id"
FROM "public"."Role" r
CROSS JOIN "public"."Permission" p
WHERE r."name" IN ('Admin', 'Manager', 'Operatore')
  AND p."resource" = 'inventory-lots'
  AND p."action" = 'view'
ON CONFLICT ("roleId", "permissionId") DO NOTHING;
