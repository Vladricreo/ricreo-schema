-- Tipo piatto richiesto su file 3MF e tipo piatto montato su stampante (Bambu).
-- Idempotente: enum e colonne gestiti con eccezione / IF NOT EXISTS (sicuro se era già stato eseguito lo script legacy in prisma/migrations/sql).

DO $$
BEGIN
  CREATE TYPE "print-farm"."PlateType" AS ENUM ('TEXTURED', 'SMOOTH', 'SMOOTH_PA');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE "print-farm"."ProjectThreeMFFile"
  ADD COLUMN IF NOT EXISTS "requiredPlateType" "print-farm"."PlateType" NOT NULL DEFAULT 'TEXTURED'::"print-farm"."PlateType";

ALTER TABLE "print-farm"."Printer"
  ADD COLUMN IF NOT EXISTS "currentPlateType" "print-farm"."PlateType" NOT NULL DEFAULT 'TEXTURED'::"print-farm"."PlateType";
