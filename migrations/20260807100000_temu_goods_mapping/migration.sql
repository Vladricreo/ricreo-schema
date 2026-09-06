-- Schema Product Console + mapping Temu externalGoodsId ↔ goodsId
CREATE SCHEMA IF NOT EXISTS "product";

CREATE TABLE "product"."TemuGoodsMapping" (
    "id" TEXT NOT NULL,
    "externalGoodsId" TEXT NOT NULL,
    "goodsId" TEXT NOT NULL,
    "externalSkuIds" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL,

    CONSTRAINT "TemuGoodsMapping_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "TemuGoodsMapping_externalGoodsId_key" ON "product"."TemuGoodsMapping"("externalGoodsId");
CREATE INDEX "TemuGoodsMapping_goodsId_idx" ON "product"."TemuGoodsMapping"("goodsId");
