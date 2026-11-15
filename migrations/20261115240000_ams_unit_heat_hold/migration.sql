-- R-221: caldo in stampa dell'unità AMS, letto dal backend dopo un riavvio.
ALTER TABLE "print-farm"."PrinterAmsUnit" ADD COLUMN "heatHoldUntil" TIMESTAMPTZ(6);
