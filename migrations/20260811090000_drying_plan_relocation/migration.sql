-- Trasferimento bobina fra AMS a fine asciugatura.
-- Sulle multinozzle senza FTS la AMS HT può stare su un ugello diverso da quello
-- richiesto dal file: si asciuga lì e poi la bobina va montata fisicamente nello
-- slot che alimenta l'ugello corretto. Queste colonne descrivono quel passo.

ALTER TABLE "print-farm"."AssignmentDryingPlan"
  ADD COLUMN IF NOT EXISTS "relocationTargetSlotId" UUID,
  ADD COLUMN IF NOT EXISTS "relocationMinutes" INTEGER,
  ADD COLUMN IF NOT EXISTS "relocationDoneAt" TIMESTAMPTZ(6);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'AssignmentDryingPlan_relocationTargetSlotId_fkey'
  ) THEN
    ALTER TABLE "print-farm"."AssignmentDryingPlan"
      ADD CONSTRAINT "AssignmentDryingPlan_relocationTargetSlotId_fkey"
      FOREIGN KEY ("relocationTargetSlotId")
      REFERENCES "print-farm"."PrinterAmsSlot"("id")
      ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS "AssignmentDryingPlan_relocationTargetSlotId_idx"
  ON "print-farm"."AssignmentDryingPlan"("relocationTargetSlotId");
