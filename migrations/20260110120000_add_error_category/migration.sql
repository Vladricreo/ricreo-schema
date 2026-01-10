-- Migration: Add ErrorCategory enum and category column to ErrorCode
-- Backfill existing rows based on severity (CRITICAL → BLOCKING, otherwise WARNING)

-- 1. Create the ErrorCategory enum
CREATE TYPE "print-farm"."ErrorCategory" AS ENUM ('WARNING', 'RECOVERABLE', 'BLOCKING', 'FILAMENT_RUNOUT', 'IGNORE');

-- 2. Add the category column with default WARNING
ALTER TABLE "print-farm"."ErrorCode" ADD COLUMN "category" "print-farm"."ErrorCategory" NOT NULL DEFAULT 'WARNING';

-- 3. Backfill: map CRITICAL severity to BLOCKING category
UPDATE "print-farm"."ErrorCode"
SET "category" = 'BLOCKING'
WHERE "severity" = 'CRITICAL';

-- 4. Create index on category for efficient lookups
CREATE INDEX "ErrorCode_category_idx" ON "print-farm"."ErrorCode"("category");
