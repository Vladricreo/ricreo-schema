-- ============================================================================
-- Migration: Remove printsExpected/printsCompleted from PrinterAssignment
-- ============================================================================

ALTER TABLE "print-farm"."PrinterAssignment"
DROP COLUMN IF EXISTS "printsExpected",
DROP COLUMN IF EXISTS "printsCompleted";

