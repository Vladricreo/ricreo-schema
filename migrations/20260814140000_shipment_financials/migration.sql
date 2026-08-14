-- Importi finanziari sincronizzati da ShippyPro GetShippedOrders:
-- total_sales, shipment_amountpaid, shipment_cost, shipment_cost_currency.

ALTER TABLE "inventory"."Shipment"
  ADD COLUMN IF NOT EXISTS "totalSales" DECIMAL(12, 2),
  ADD COLUMN IF NOT EXISTS "salesCurrency" VARCHAR(3),
  ADD COLUMN IF NOT EXISTS "customerShippingCost" DECIMAL(12, 2),
  ADD COLUMN IF NOT EXISTS "shippingCost" DECIMAL(12, 2),
  ADD COLUMN IF NOT EXISTS "shippingCostCurrency" VARCHAR(3);
