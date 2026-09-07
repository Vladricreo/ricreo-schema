-- Data obiettivo di completamento dell'ordine di assemblaggio (override manuale).
-- Se NULL, la UI usa la dueDate più vicina dei Production Order collegati.
ALTER TABLE "inventory"."AssemblyOrder" ADD COLUMN "dueDate" TIMESTAMPTZ(6);
