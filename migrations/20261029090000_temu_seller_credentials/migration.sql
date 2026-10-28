-- ============================================================================
-- Token Temu per mercato (29/10/2026).
--
-- Su Temu EU ogni mercato (IT, DE, FR, NL, BE, GB…) è un mall a sé con la sua
-- autorizzazione in Seller Center. Con il solo token IT gli ordini PO-076 (DE),
-- PO-141 (NL)… rispondono «Order not found» e restano con commissioni stimate.
-- Qui un access token cifrato per mercato, aggiornabile da Impostazioni →
-- Connessioni.
-- ============================================================================

CREATE TABLE "product"."TemuSellerCredential" (
    "id" TEXT NOT NULL,
    "market" TEXT NOT NULL,
    "accessToken" TEXT NOT NULL,
    "mallId" TEXT,
    "expiresAt" TIMESTAMPTZ(6),
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "TemuSellerCredential_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "TemuSellerCredential_market_key" ON "product"."TemuSellerCredential"("market");
