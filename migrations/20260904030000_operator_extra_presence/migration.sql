-- ============================================================================
-- Calendario operatore 4.6 — presenza extra ad-hoc e chiusure aziendali.
-- (audit 2026-09-03: PIANO-AZIONE ondata 4, punto 4.6; MODELLO-DOMANDA
--  sezione "Operatori": presenze informali fuori turno, anche weekend/sera;
--  capacità condivisa a valore variabile, non slot fissi per reparto)
--
-- Cosa cambia:
--   * Nuova tabella "print-farm"."OperatorExtraPresence": dichiarazione
--     leggera di presenza fuori turno ("domani ci sono 2h") legata a un
--     utente. Si AGGIUNGE alle finestre da WorkShift − WorkAbsence nello
--     snapshot di presenza del gate F1
--     (client/src/lib/scheduler/operator-presence.ts).
--   * Nuova tabella "print-farm"."CompanyHoliday": chiusura aziendale di un
--     giorno (festività, ponti, chiusura estiva). In quel giorno i turni
--     ricorrenti non producono presenza per NESSUN operatore.
--
-- Perché CompanyHoliday e non il riuso di WorkAbsence con un marker:
-- WorkAbsence è per-utente (@@unique(userId, absenceDate)) — una chiusura
-- aziendale richiederebbe N righe (una per operatore) da tenere allineate a
-- ogni cambio di organico, più una convenzione testuale da riconoscere in
-- lettura. Una riga per giorno di chiusura è più semplice e si legge
-- direttamente nel window builder: il giorno festivo azzera i turni di
-- tutti, mentre una presenza extra dichiarata esplicitamente resta valida
-- (è un segnale deliberato, vedi operator-presence.ts).
--
-- Tutto additivo e idempotente (IF NOT EXISTS): nessuna tabella esistente
-- viene toccata e il codice in produzione (vecchio) ignora le nuove tabelle.
--
-- Applicabile anche via psql / Supabase SQL editor. Se lo fai fuori da Prisma:
--   bunx prisma migrate resolve --applied 20260904030000_operator_extra_presence
-- ============================================================================

CREATE TABLE IF NOT EXISTS "print-farm"."OperatorExtraPresence" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "userId" INTEGER NOT NULL,
    -- Giorno della presenza extra (solo data, stessa convenzione @db.Date di WorkAbsence).
    "date" DATE NOT NULL,
    -- Minuti dalla mezzanotte LOCALE (es. 1200 = 20:00); toMinute <= fromMinute = overnight.
    "fromMinute" SMALLINT NOT NULL,
    "toMinute" SMALLINT NOT NULL,
    "note" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT now(),
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT now(),

    CONSTRAINT "OperatorExtraPresence_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "OperatorExtraPresence_minutes_check"
        CHECK ("fromMinute" BETWEEN 0 AND 1439 AND "toMinute" BETWEEN 0 AND 1439),
    CONSTRAINT "OperatorExtraPresence_userId_fkey"
        FOREIGN KEY ("userId") REFERENCES "public"."User"("id")
        ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX IF NOT EXISTS "OperatorExtraPresence_userId_idx"
    ON "print-farm"."OperatorExtraPresence"("userId");

CREATE INDEX IF NOT EXISTS "OperatorExtraPresence_date_idx"
    ON "print-farm"."OperatorExtraPresence"("date");

CREATE TABLE IF NOT EXISTS "print-farm"."CompanyHoliday" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    -- Giorno di chiusura aziendale (solo data).
    "date" DATE NOT NULL,
    "note" TEXT,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT now(),
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT now(),

    CONSTRAINT "CompanyHoliday_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "CompanyHoliday_date_key"
    ON "print-farm"."CompanyHoliday"("date");
