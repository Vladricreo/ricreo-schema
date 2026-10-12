-- Fatture FedEx Express Italy importate da PDF: nuovo corriere accanto a UPS.
-- Solo estensione dell'enum del nostro schema `product`, nessun dato esistente toccato.

-- AlterEnum
ALTER TYPE "product"."CarrierCode" ADD VALUE IF NOT EXISTS 'FEDEX';
