-- Optimistic locking per ordini di assemblaggio (concorrenza UI)
ALTER TABLE inventory."AssemblyOrder"
ADD COLUMN IF NOT EXISTS "version" INTEGER NOT NULL DEFAULT 0;
