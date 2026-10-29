-- Tablet condiviso: PIN per persona (29/10, R-150).
--
-- Su un tablet usato da più persone admin e manager entrano col tocco sul proprio
-- avatar più un PIN di 4 cifre; gli altri solo col tocco, a meno che non abbiano un PIN.
-- Il PIN è uno per persona e vale in tutte le app (Inventory e Print Farm): si salva
-- solo l'hash (scrypt) in Profile.tabletPinHash.
--
-- Idempotente e additiva: colonna facoltativa con IF NOT EXISTS.

ALTER TABLE "public"."Profile"
  ADD COLUMN IF NOT EXISTS "tabletPinHash" TEXT;
