-- B-3 (A-335, 15/11, audit Bambuddy): impostazione «AMS Filament Backup» della
-- stampante (ricarico automatico), letta dal backend dalla telemetria (`cfg`
-- bit 18, `home_flag` bit 10). Colonna nullable, nessun dato esistente toccato:
-- null = mai letto, e il piano bobine si comporta come prima. Il backend è
-- fail-open: senza la colonna non scrive niente.

-- AlterTable
ALTER TABLE "print-farm"."Printer" ADD COLUMN "amsFilamentBackupEnabled" BOOLEAN;
