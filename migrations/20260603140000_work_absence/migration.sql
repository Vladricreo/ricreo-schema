-- Assenze puntuali operatore (giorno specifico): capacità 0 in distribuzione assemblaggi.

CREATE TABLE IF NOT EXISTS "public"."WorkAbsence" (
  "id" SERIAL NOT NULL,
  "userId" INTEGER NOT NULL,
  "absenceDate" DATE NOT NULL,
  "note" TEXT,
  "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "WorkAbsence_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "WorkAbsence_userId_absenceDate_key"
  ON "public"."WorkAbsence"("userId", "absenceDate");
CREATE INDEX IF NOT EXISTS "WorkAbsence_userId_idx"
  ON "public"."WorkAbsence"("userId");
CREATE INDEX IF NOT EXISTS "WorkAbsence_absenceDate_idx"
  ON "public"."WorkAbsence"("absenceDate");

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'WorkAbsence_userId_fkey'
  ) THEN
    ALTER TABLE "public"."WorkAbsence"
      ADD CONSTRAINT "WorkAbsence_userId_fkey"
      FOREIGN KEY ("userId") REFERENCES "public"."User"("id")
      ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END $$;

COMMENT ON TABLE "public"."WorkAbsence"
  IS 'Giorni di assenza puntuali: in distribuzione assemblaggi capacità operatore = 0.';
COMMENT ON COLUMN "public"."WorkAbsence"."absenceDate"
  IS 'Giorno di calendario in cui l''operatore è assente.';
