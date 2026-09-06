-- Lock TTL per le risorse assegnate dalla preparazione live.
CREATE TYPE "print-farm"."PreparationReservationKind" AS ENUM (
    'SPOOL',
    'UNLOAD_LOCATION',
    'AMS_SLOT'
);

CREATE TABLE "print-farm"."PreparationReservation" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "spoolId" UUID,
    "locationId" UUID,
    "amsSlotId" UUID,
    "printerId" UUID NOT NULL,
    "assignmentId" UUID,
    "kind" "print-farm"."PreparationReservationKind" NOT NULL,
    "expiresAt" TIMESTAMPTZ(6) NOT NULL,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "PreparationReservation_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "PreparationReservation_spoolId_key"
    ON "print-farm"."PreparationReservation"("spoolId");
CREATE UNIQUE INDEX "PreparationReservation_locationId_key"
    ON "print-farm"."PreparationReservation"("locationId");
CREATE UNIQUE INDEX "PreparationReservation_amsSlotId_key"
    ON "print-farm"."PreparationReservation"("amsSlotId");
CREATE INDEX "PreparationReservation_printerId_expiresAt_idx"
    ON "print-farm"."PreparationReservation"("printerId", "expiresAt");
CREATE INDEX "PreparationReservation_assignmentId_expiresAt_idx"
    ON "print-farm"."PreparationReservation"("assignmentId", "expiresAt");
CREATE INDEX "PreparationReservation_expiresAt_idx"
    ON "print-farm"."PreparationReservation"("expiresAt");
