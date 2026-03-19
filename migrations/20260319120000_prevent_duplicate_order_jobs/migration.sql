DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM "print-farm"."ProductionJob"
    WHERE "productOrderId" IS NOT NULL
      AND "productPartId" IS NOT NULL
    GROUP BY "productOrderId", "productPartId"
    HAVING COUNT(*) > 1
  ) THEN
    RAISE EXCEPTION 'Impossibile aggiungere il vincolo unico ProductionJob(productOrderId, productPartId): esistono gia duplicati da bonificare.';
  END IF;
END $$;

CREATE UNIQUE INDEX "ProductionJob_productOrderId_productPartId_key"
ON "print-farm"."ProductionJob"("productOrderId", "productPartId");
