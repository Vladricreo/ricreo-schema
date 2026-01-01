-- Align index on inventory.Movement(date) with Prisma schema.
-- Reason: manual SQL created a DESC index (`idx_movement_date`) which causes Prisma drift
-- vs the migration history index (`Movement_date_idx`).
--
-- Safe: DDL only (no data changes). Rebuilds the index with a canonical name + DESC order.

-- Remove any manually created index name (from SQL editor)
DROP INDEX IF EXISTS "inventory"."idx_movement_date";

-- Remove the historical Prisma index (might exist with ASC order)
DROP INDEX IF EXISTS "inventory"."Movement_date_idx";

-- Recreate with canonical name + DESC (matches @@index([date(sort: Desc)]))
CREATE INDEX "Movement_date_idx" ON "inventory"."Movement" ("date" DESC);

