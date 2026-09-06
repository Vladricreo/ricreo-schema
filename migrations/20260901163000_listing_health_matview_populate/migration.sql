-- Primo populate delle matview salute listing (create WITH NO DATA
-- in 20260901160000_listing_ignored_sku). Senza questo la dashboard
-- /dashboard/listings va in 500: "has not been populated".
-- CONCURRENTLY non è usabile: le matview non sono ancora state lette.

REFRESH MATERIALIZED VIEW "product"."mv_listing_health_current";
REFRESH MATERIALIZED VIEW "product"."mv_listing_sales_returns_30d";
REFRESH MATERIALIZED VIEW "product"."mv_listing_bsr_trend";
REFRESH MATERIALIZED VIEW "product"."mv_listing_review_alert";
REFRESH MATERIALIZED VIEW "product"."mv_listing_health_store_stats";
