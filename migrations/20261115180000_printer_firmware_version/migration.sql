-- M-10 (A-314, 15/11, audit Bambuddy): versione firmware della stampante letta
-- dal backend con `info.get_version` (modulo `ota`). Due colonne nullable, nessun
-- dato esistente toccato. Il backend è fail-open: senza le colonne tiene la
-- versione solo in memoria e Impostazioni → Firmware la mostra dal live.

-- AlterTable
ALTER TABLE "print-farm"."Printer" ADD COLUMN "firmwareVersion" VARCHAR(40),
ADD COLUMN "firmwareVersionUpdatedAt" TIMESTAMPTZ(6);
