-- ---------------------------------------------------------------------------
-- Singleton con l'ultimo refresh delle matview della pagina Vendite.
-- Serve alla UI per dire "aggiornato N minuti fa": senza questa riga il
-- bottone Aggiorna non saprebbe distinguere dati freschi da dati di un'ora fa.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "product"."SalesAnalyticsRefresh" (
  "id"          INTEGER      NOT NULL DEFAULT 1,
  "refreshedAt" TIMESTAMPTZ(6) NOT NULL,
  "rowCount"    INTEGER      NOT NULL DEFAULT 0,
  "durationMs"  INTEGER      NOT NULL DEFAULT 0,
  "source"      TEXT         NOT NULL DEFAULT 'cron',

  CONSTRAINT "SalesAnalyticsRefresh_pkey" PRIMARY KEY ("id")
);
