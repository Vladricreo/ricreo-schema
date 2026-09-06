# Snapshot pre-fix (2026-09-06)

Captured via `pg_get_viewdef` / `pg_get_indexdef` before applying
`20260906180000_overview_sold_vat_refund_fixes`.

> **Nota:** questa cartella NON sta in `migrations/`. Prisma tratta ogni
> sottocartella di `migrations/` come una migration e richiede
> `migration.sql` (errore P3015 se manca). Gli snapshot restano qui
> solo come documentazione.

## Pre-change 30d (CURRENT_DATE-29 .. CURRENT_DATE)

- KPI profit (sales_daily): €22,262.56
- Country profit: €26,147.39
- Fulfillment profit: €26,147.39
- Gap country/fulfillment vs KPI: €3,884.83
- KPI gross / units: €89,540.18 / 4,653
- Refund referral (includes DSF): €1,826.62
- Amazon shipped-only gross / units: €82,872.80 / 4,419
- Amazon Unshipped (excluded): €4,363.97 / 336 units
- Seasonality 2026-08 Amazon: 3,968 u / €85,012.31 (Europe/Rome + mixed currency)

## Indexes

See `indexes.sql`.
