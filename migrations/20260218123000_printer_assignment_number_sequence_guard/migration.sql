-- Riallinea subito la sequence al massimo numero presente.
SELECT setval(
  '"print-farm"."PrinterAssignment_number_seq"',
  GREATEST(
    (SELECT COALESCE(MAX("number"), 0) FROM "print-farm"."PrinterAssignment"),
    1
  ),
  true
);

-- Mantiene la sequence sempre avanti quando vengono inseriti/forzati numeri espliciti.
-- Questo evita drift dopo import/restore o insert manuali con "number" valorizzato.
CREATE OR REPLACE FUNCTION "print-farm".sync_printer_assignment_number_seq()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM setval(
    '"print-farm"."PrinterAssignment_number_seq"',
    GREATEST(
      (SELECT COALESCE(MAX("number"), 0) FROM "print-farm"."PrinterAssignment"),
      1
    ),
    true
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_printer_assignment_number_seq
ON "print-farm"."PrinterAssignment";

CREATE TRIGGER trg_sync_printer_assignment_number_seq
AFTER INSERT OR UPDATE OF "number"
ON "print-farm"."PrinterAssignment"
FOR EACH ROW
EXECUTE FUNCTION "print-farm".sync_printer_assignment_number_seq();
