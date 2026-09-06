-- F5: piani spool concreti e reservation slot con scadenza.
CREATE TYPE "print-farm"."AssignmentSpoolPlanStatus" AS ENUM (
  'PLANNED',
  'LOADED',
  'CONSUMED',
  'CANCELLED'
);

CREATE TYPE "print-farm"."AssignmentSpoolPlanProvenance" AS ENUM (
  'OPEN_SPOOL',
  'SEALED_INVENTORY'
);

CREATE TYPE "print-farm"."AssignmentSpoolPlanVerification" AS ENUM (
  'VERIFIED',
  'OPERATOR_REVIEW_REQUIRED'
);

CREATE TABLE "print-farm"."AssignmentSpoolPlan" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "assignmentId" UUID NOT NULL,
  "fileFilamentIndex" INTEGER NOT NULL,
  "sequence" INTEGER NOT NULL,
  "spoolId" UUID,
  "itemId" UUID,
  "plannedGrams" DECIMAL(10,2) NOT NULL,
  "amsUnit" INTEGER,
  "slot" INTEGER,
  "status" "print-farm"."AssignmentSpoolPlanStatus" NOT NULL DEFAULT 'PLANNED',
  "provenance" "print-farm"."AssignmentSpoolPlanProvenance" NOT NULL,
  "verification" "print-farm"."AssignmentSpoolPlanVerification" NOT NULL DEFAULT 'OPERATOR_REVIEW_REQUIRED',
  "automationEligible" BOOLEAN NOT NULL DEFAULT false,
  "reservedSlotId" UUID,
  "reservationExpiresAt" TIMESTAMPTZ(6),
  "planVersion" INTEGER NOT NULL DEFAULT 1,
  "plannedBy" TEXT NOT NULL DEFAULT 'scheduler-f5-v1',
  "metadata" JSONB,
  "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "AssignmentSpoolPlan_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "AssignmentSpoolPlan_assignmentId_fileFilamentIndex_sequence_key"
  ON "print-farm"."AssignmentSpoolPlan"("assignmentId", "fileFilamentIndex", "sequence");
CREATE UNIQUE INDEX "AssignmentSpoolPlan_reservedSlotId_key"
  ON "print-farm"."AssignmentSpoolPlan"("reservedSlotId");
CREATE INDEX "AssignmentSpoolPlan_assignmentId_idx"
  ON "print-farm"."AssignmentSpoolPlan"("assignmentId");
CREATE INDEX "AssignmentSpoolPlan_spoolId_idx"
  ON "print-farm"."AssignmentSpoolPlan"("spoolId");
CREATE INDEX "AssignmentSpoolPlan_itemId_idx"
  ON "print-farm"."AssignmentSpoolPlan"("itemId");
CREATE INDEX "AssignmentSpoolPlan_reservedSlotId_reservationExpiresAt_idx"
  ON "print-farm"."AssignmentSpoolPlan"("reservedSlotId", "reservationExpiresAt");
CREATE INDEX "AssignmentSpoolPlan_status_idx"
  ON "print-farm"."AssignmentSpoolPlan"("status");

ALTER TABLE "print-farm"."AssignmentSpoolPlan"
  ADD CONSTRAINT "AssignmentSpoolPlan_assignmentId_fkey"
  FOREIGN KEY ("assignmentId")
  REFERENCES "print-farm"."PrinterAssignment"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "print-farm"."AssignmentSpoolPlan"
  ADD CONSTRAINT "AssignmentSpoolPlan_spoolId_fkey"
  FOREIGN KEY ("spoolId")
  REFERENCES "print-farm"."FilamentSpool"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "print-farm"."AssignmentSpoolPlan"
  ADD CONSTRAINT "AssignmentSpoolPlan_itemId_fkey"
  FOREIGN KEY ("itemId")
  REFERENCES "inventory"."Item"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "print-farm"."AssignmentSpoolPlan"
  ADD CONSTRAINT "AssignmentSpoolPlan_reservedSlotId_fkey"
  FOREIGN KEY ("reservedSlotId")
  REFERENCES "print-farm"."PrinterAmsSlot"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;
