-- E-3 (R-209, 15/11, audit Bambuddy): una stampa annullata dallo schermo o da
-- uno stop dell'app resta FAILED ma porta il motivo, così non conta
-- nell'affidabilità della stampante né nei cruscotti dei falliti. Colonna
-- nullable, nessun dato esistente toccato. Il backend è fail-open senza la colonna.

-- AlterTable
ALTER TABLE "print-farm"."PrintRun" ADD COLUMN "endReason" VARCHAR(40);
