-- Ripristina SettingsName dopo uno swap enum incompleto:
-- Settings.name e le view puntavano a SettingsName_old,
-- mentre Prisma/query usavano SettingsName (tipo orfano senza ASSEMBLY_BASE_TIME_PER_PIECE).

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_type t
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'inventory'
      AND t.typname = 'SettingsName_old'
  ) THEN
    -- Rimuove il tipo orfano solo se SettingsName_old esiste ancora da ripristinare.
    IF EXISTS (
      SELECT 1
      FROM pg_type t
      JOIN pg_namespace n ON n.oid = t.typnamespace
      WHERE n.nspname = 'inventory'
        AND t.typname = 'SettingsName'
    ) AND NOT EXISTS (
      SELECT 1
      FROM pg_attribute a
      JOIN pg_class c ON a.attrelid = c.oid
      JOIN pg_namespace n ON c.relnamespace = n.oid
      JOIN pg_type t ON a.atttypid = t.oid
      JOIN pg_namespace tn ON t.typnamespace = tn.oid
      WHERE n.nspname = 'inventory'
        AND c.relname = 'Settings'
        AND a.attname = 'name'
        AND tn.nspname = 'inventory'
        AND t.typname = 'SettingsName'
    ) THEN
      DROP TYPE inventory."SettingsName";
    END IF;

    ALTER TYPE inventory."SettingsName_old" RENAME TO "SettingsName";
  END IF;
END $$;
