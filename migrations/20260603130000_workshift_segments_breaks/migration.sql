-- Supporto pause nei turni: un giorno può avere più segmenti di turno.
-- Rimuoviamo il vincolo di unicità (userId, dayOfWeek) che limitava a un solo
-- segmento per giorno. Le pause sono gli intervalli non coperti tra i segmenti.
--
-- Idempotente: il DROP CONSTRAINT usa IF EXISTS.

ALTER TABLE "public"."WorkShift"
  DROP CONSTRAINT IF EXISTS "WorkShift_userId_dayOfWeek_key";

-- Prisma crea anche un indice unico con lo stesso nome: rimuoviamolo se presente.
DROP INDEX IF EXISTS "public"."WorkShift_userId_dayOfWeek_key";
