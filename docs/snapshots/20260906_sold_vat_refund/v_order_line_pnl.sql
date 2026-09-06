-- Snapshot live 2026-09-06: product.v_order_line_pnl
-- is_sold = itemStatus IS NULL OR '' OR 'Shipped'
-- vat_local = itemTax + shippingTax (eBay forced 0); no VAT fallback; no gift wrap
SELECT pg_get_viewdef('product.v_order_line_pnl'::regclass, true);
