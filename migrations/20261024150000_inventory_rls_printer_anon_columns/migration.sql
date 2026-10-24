-- Sicurezza delle API Supabase (applicata a mano sul DB il 24/10/2026, qui per
-- traccia: le istruzioni sono idempotenti e si possono rieseguire).

-- 1) RLS su tutte le tabelle dello schema inventory, senza policy: le app le
--    leggono solo via Prisma come `postgres` (proprietario, non soggetto a RLS);
--    anon e authenticated non devono vederle dalle API.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT c.relname FROM pg_class c JOIN pg_namespace ns ON ns.oid = c.relnamespace
    WHERE ns.nspname = 'inventory' AND c.relkind IN ('r', 'p') AND NOT c.relrowsecurity
  LOOP
    EXECUTE format('ALTER TABLE inventory.%I ENABLE ROW LEVEL SECURITY', r.relname);
  END LOOP;
END $$;

-- 2) print-farm.Printer: anon serve solo al Realtime delle schermate Print Farm
--    (client del browser con la chiave pubblica). Niente lettura delle
--    credenziali delle stampanti: SELECT solo sulle altre colonne. Le colonne
--    aggiunte in futuro non arrivano ad anon finché non si rilancia questo blocco.
REVOKE SELECT ON "print-farm"."Printer" FROM anon;
DO $$
DECLARE cols text;
BEGIN
  SELECT string_agg(format('%I', a.attname), ', ' ORDER BY a.attnum) INTO cols
  FROM pg_attribute a
  WHERE a.attrelid = '"print-farm"."Printer"'::regclass AND a.attnum > 0 AND NOT a.attisdropped
    AND a.attname NOT IN ('accessCode', 'apiKey', 'ipAddress');
  EXECUTE format('GRANT SELECT (%s) ON "print-farm"."Printer" TO anon', cols);
END $$;
