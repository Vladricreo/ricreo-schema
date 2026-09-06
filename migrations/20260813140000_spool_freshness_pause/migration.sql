-- La validita dell'asciugatura non scorre mentre la bobina sta in una AMS che
-- asciuga (HT / 2 Pro). `freshnessPausedAt` congela l'orologio; allo smontaggio
-- verso rack o AMS senza asciugatura si riparte da li.

ALTER TABLE "print-farm"."FilamentSpool"
  ADD COLUMN IF NOT EXISTS "freshnessPausedAt" TIMESTAMPTZ(6);

-- Bobine gia montate in HT / 2 Pro: parti da adesso, senza accreditare il tempo
-- passato in unita (non e noto quando sono entrate).
UPDATE "print-farm"."FilamentSpool" AS s
SET "freshnessPausedAt" = NOW()
WHERE s."lastDriedAt" IS NOT NULL
  AND s."freshnessPausedAt" IS NULL
  AND EXISTS (
    SELECT 1
    FROM "print-farm"."PrinterAmsSlot" AS sl
    LEFT JOIN "print-farm"."PrinterAmsUnit" AS u_fk
      ON u_fk."id" = sl."amsUnitId"
    LEFT JOIN "print-farm"."PrinterAmsUnit" AS u_legacy
      ON u_legacy."printerId" = sl."printerId"
      AND u_legacy."amsId" = sl."amsUnit"
    WHERE sl."spoolId" = s."id"
      AND COALESCE(u_fk."amsModel", u_legacy."amsModel")::text IN ('AMS_HT', 'AMS_2_PRO')
  );
