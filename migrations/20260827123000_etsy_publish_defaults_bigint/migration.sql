-- ID Etsy (shipping profile / readiness / taxonomy) non stanno in INTEGER.
-- Solo schema product.

ALTER TABLE "product"."CrossplatformPublishDefaults"
  ALTER COLUMN "etsyTaxonomyId" TYPE BIGINT,
  ALTER COLUMN "etsyShippingProfileId" TYPE BIGINT,
  ALTER COLUMN "etsyReadinessStateId" TYPE BIGINT;
