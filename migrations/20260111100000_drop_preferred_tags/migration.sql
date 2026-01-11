-- Drop preferredTags column from Printer table
-- This column has been replaced by the PrinterPreferredMaterialCategory M2M relation

ALTER TABLE "print-farm"."Printer" DROP COLUMN IF EXISTS "preferredTags";
