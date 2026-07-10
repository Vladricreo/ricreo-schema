INSERT INTO "inventory"."Settings" ("id", "name", "value", "createdAt", "updatedAt")
VALUES (
  gen_random_uuid(),
  'PRODUCTION_MIN_BATCH_QTY',
  '5'::jsonb,
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
)
ON CONFLICT ("name") DO NOTHING;
