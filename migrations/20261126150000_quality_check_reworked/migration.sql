-- «Rifai tutto» con un controllo solo (R-319, cambiata il 26/11/2026).
--
-- Il «Rifai» chiude il controllo con lo stato REWORKED («Da rifare»): i pezzi si sbloccano
-- come con una firma, l'anomalia resta registrata e l'operatore conferma di aver sistemato
-- («Ho sistemato, continuo»). Niente più secondo giro: REWORK resta nell'enum ma non si crea.
--
-- Solo aggiunte, ripetibile. REWORKED non entra nell'indice univoco del controllo aperto:
-- è uno stato chiuso.
--
-- ALTER TYPE ... ADD VALUE non si può usare nella stessa transazione in cui il valore nuovo
-- viene letto o scritto: qui non lo si usa.

ALTER TYPE "inventory"."QualityCheckStatus" ADD VALUE IF NOT EXISTS 'REWORKED';

ALTER TABLE "inventory"."QualityCheck"
  ADD COLUMN IF NOT EXISTS "reworkFixedAt" TIMESTAMPTZ(6),
  ADD COLUMN IF NOT EXISTS "reworkFixedByUserId" INTEGER;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'QualityCheck_reworkFixedByUserId_fkey'
  ) THEN
    ALTER TABLE "inventory"."QualityCheck"
      ADD CONSTRAINT "QualityCheck_reworkFixedByUserId_fkey" FOREIGN KEY ("reworkFixedByUserId")
      REFERENCES "public"."User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS "QualityCheck_reworkFixedByUserId_idx"
  ON "inventory"."QualityCheck"("reworkFixedByUserId");

COMMENT ON COLUMN "inventory"."QualityCheck"."reworkFixedAt" IS
  'Stato REWORKED: quando l''operatore ha confermato di aver sistemato i pezzi («Ho sistemato, continuo»). Nullo = non confermato.';
COMMENT ON COLUMN "inventory"."QualityCheck"."reworkFixedByUserId" IS
  'Stato REWORKED: chi ha confermato di aver sistemato i pezzi.';
