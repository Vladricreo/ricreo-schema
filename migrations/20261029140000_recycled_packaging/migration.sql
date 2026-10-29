-- ============================================================================
-- Packaging riciclati (29/10/2026, R-136).
--
-- Scatole di recupero con le misure esterne (mm). Dalla pagina «Dimensioni
-- scaffali» si importano come misure del pacco di uno SKU: l'app propone la
-- più piccola in cui entra il packaging secondario dello SKU.
-- ============================================================================

CREATE TABLE "inventory"."RecycledPackaging" (
    "id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "widthMm" INTEGER NOT NULL,
    "depthMm" INTEGER NOT NULL,
    "heightMm" INTEGER NOT NULL,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "RecycledPackaging_pkey" PRIMARY KEY ("id")
);

-- Come le altre tabelle inventory (24/10): RLS attiva, nessuna policy.
ALTER TABLE "inventory"."RecycledPackaging" ENABLE ROW LEVEL SECURITY;
