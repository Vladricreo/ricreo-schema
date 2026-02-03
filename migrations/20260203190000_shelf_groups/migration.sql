-- CreateTable
CREATE TABLE "inventory"."WarehouseShelfGroup" (
    "id" UUID NOT NULL,
    "code" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT,
    "order" INTEGER NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT now(),
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT now(),

    CONSTRAINT "WarehouseShelfGroup_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "WarehouseShelfGroup_code_key" ON "inventory"."WarehouseShelfGroup"("code");
CREATE UNIQUE INDEX "WarehouseShelfGroup_order_key" ON "inventory"."WarehouseShelfGroup"("order");

-- AlterTable
ALTER TABLE "inventory"."WarehouseShelf"
ADD COLUMN     "groupId" UUID,
ADD COLUMN     "positionInGroup" INTEGER;

-- Backfill groups from existing lineCode
INSERT INTO "inventory"."WarehouseShelfGroup" ("id", "code", "name", "description", "order")
SELECT
  gen_random_uuid() AS "id",
  lc."lineCode" AS "code",
  ('Fila ' || lc."lineCode") AS "name",
  NULL AS "description",
  ROW_NUMBER() OVER (ORDER BY lc."lineCode" ASC) AS "order"
FROM (
  SELECT DISTINCT "lineCode"
  FROM "inventory"."WarehouseShelf"
  WHERE "lineCode" IS NOT NULL AND btrim("lineCode") <> ''
) lc;

-- Set groupId based on matching lineCode
UPDATE "inventory"."WarehouseShelf" s
SET "groupId" = g."id"
FROM "inventory"."WarehouseShelfGroup" g
WHERE s."lineCode" = g."code";

-- Normalize shelf positions inside each group to 1..N
WITH ranked AS (
  SELECT
    s."id" AS shelf_id,
    s."groupId" AS group_id,
    ROW_NUMBER() OVER (
      PARTITION BY s."groupId"
      ORDER BY COALESCE(s."indexInLine", 2147483647) ASC, s."code" ASC
    ) AS rn
  FROM "inventory"."WarehouseShelf" s
  WHERE s."groupId" IS NOT NULL
)
UPDATE "inventory"."WarehouseShelf" s
SET "positionInGroup" = ranked.rn
FROM ranked
WHERE s."id" = ranked.shelf_id;

-- CreateIndex
CREATE INDEX "WarehouseShelf_groupId_positionInGroup_idx"
ON "inventory"."WarehouseShelf"("groupId", "positionInGroup");

-- AddForeignKey
ALTER TABLE "inventory"."WarehouseShelf"
ADD CONSTRAINT "WarehouseShelf_groupId_fkey"
FOREIGN KEY ("groupId") REFERENCES "inventory"."WarehouseShelfGroup"("id")
ON DELETE SET NULL ON UPDATE CASCADE;

-- Drop old columns and index
DROP INDEX IF EXISTS "inventory"."WarehouseShelf_lineCode_indexInLine_idx";
ALTER TABLE "inventory"."WarehouseShelf" DROP COLUMN "lineCode";
ALTER TABLE "inventory"."WarehouseShelf" DROP COLUMN "indexInLine";

