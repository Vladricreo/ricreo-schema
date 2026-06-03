-- Supabase Storage: bucket privati + lettura consentita solo a utenti Supabase autenticati.
-- Le API server del client continuano a usare la service role, che bypassa le policy RLS.

-- Converte URL pubblici legacy del bucket print-farm in URL proxy same-origin prima di chiudere il bucket.
UPDATE "print-farm"."PrinterMaintenanceLog"
SET "pdfUrl" = '/api/storage/' || split_part("pdfUrl", '/storage/v1/object/public/print-farm/', 2)
WHERE "pdfUrl" LIKE '%/storage/v1/object/public/print-farm/%';

UPDATE "print-farm"."PrinterMaintenanceLog" log
SET "photos" = normalized.photos
FROM (
  SELECT
    id,
    array_agg(
      CASE
        WHEN photo LIKE '%/storage/v1/object/public/print-farm/%'
          THEN '/api/storage/' || split_part(photo, '/storage/v1/object/public/print-farm/', 2)
        ELSE photo
      END
      ORDER BY ord
    ) AS photos
  FROM "print-farm"."PrinterMaintenanceLog"
  CROSS JOIN LATERAL unnest("photos") WITH ORDINALITY AS photo_item(photo, ord)
  WHERE "photos" IS NOT NULL
  GROUP BY id
) normalized
WHERE log.id = normalized.id
  AND EXISTS (
    SELECT 1
    FROM unnest(log."photos") AS existing_photo(photo)
    WHERE photo LIKE '%/storage/v1/object/public/print-farm/%'
  );

-- Il flag public bypassa le policy sugli oggetti: va disattivato sui bucket applicativi.
UPDATE storage.buckets
SET public = false
WHERE id IN ('print-farm', 'inventory');

DROP POLICY IF EXISTS "storage_authenticated_read_app_buckets" ON storage.objects;

CREATE POLICY "storage_authenticated_read_app_buckets"
ON storage.objects
FOR SELECT
TO authenticated
USING (bucket_id IN ('print-farm', 'inventory'));
