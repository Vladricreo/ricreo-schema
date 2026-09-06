-- Snapshot live 2026-09-06: indexes on touched matviews
CREATE INDEX mv_order_seasonality_channel_month ON product.mv_order_seasonality USING btree (channel, month);
CREATE UNIQUE INDEX mv_order_seasonality_pk ON product.mv_order_seasonality USING btree (year, month, channel, sku);
CREATE INDEX mv_order_seasonality_sku ON product.mv_order_seasonality USING btree (sku);
CREATE UNIQUE INDEX mv_overview_country_daily_day_country_uidx ON product.mv_overview_country_daily USING btree (day, country_code);
CREATE UNIQUE INDEX mv_overview_fulfillment_daily_day_fulfillment_uidx ON product.mv_overview_fulfillment_daily USING btree (day, fulfillment);
CREATE UNIQUE INDEX mv_overview_sales_daily_day_channel_uidx ON product.mv_overview_sales_daily USING btree (day, channel);
CREATE UNIQUE INDEX mv_overview_sku_daily_day_channel_sku_uidx ON product.mv_overview_sku_daily USING btree (day, channel, sku);
CREATE INDEX mv_overview_sku_daily_sku_idx ON product.mv_overview_sku_daily USING btree (sku);
CREATE UNIQUE INDEX mv_overview_sku_meta_sku_uidx ON product.mv_overview_sku_meta USING btree (sku);
CREATE INDEX mv_sales_analytics_daily_day_idx ON product.mv_sales_analytics_daily USING btree (day);
CREATE UNIQUE INDEX mv_sales_analytics_daily_grain_uidx ON product.mv_sales_analytics_daily USING btree (day, channel, store_key, sales_channel, sku, fulfillment, ship_country);
CREATE INDEX mv_sales_analytics_daily_sku_day_idx ON product.mv_sales_analytics_daily USING btree (sku, day);
CREATE UNIQUE INDEX mv_sales_analytics_refund_daily_grain_uidx ON product.mv_sales_analytics_refund_daily USING btree (day, channel, store_key, sku);
CREATE INDEX mv_sales_analytics_refund_daily_sku_day_idx ON product.mv_sales_analytics_refund_daily USING btree (sku, day);
