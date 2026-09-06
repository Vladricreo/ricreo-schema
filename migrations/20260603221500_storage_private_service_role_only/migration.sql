-- Supabase Storage: bucket privati, accesso applicativo via service role/proxy NextAuth.
-- Non usiamo Supabase Auth per gli utenti, quindi una policy TO authenticated non rappresenta
-- l'autenticazione reale dell'app e viene rimossa.

DROP POLICY IF EXISTS "storage_authenticated_read_app_buckets" ON storage.objects;

-- Mantiene i bucket applicativi privati: frontend e backend accedono server-side con service role.
UPDATE storage.buckets
SET public = false
WHERE id IN ('print-farm', 'inventory');
