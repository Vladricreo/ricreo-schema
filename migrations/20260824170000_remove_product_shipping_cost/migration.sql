-- Rimuove la stima spedizione dal costo prodotto: era fuorviante.
-- La view v_product_pricing_summary dipendeva da inventory.Product.shippingCost,
-- quindi va ricreata prima di eliminare la colonna.

DROP VIEW IF EXISTS inventory_views.v_product_pricing_summary;

ALTER TABLE inventory."Product" DROP COLUMN IF EXISTS "shippingCost";

-- Fonte: prisma/custom_migrations/sql/product_cost_views.sql
CREATE VIEW inventory_views.v_product_pricing_summary AS
WITH settings_margin AS (
    SELECT
        CASE
            WHEN value::text ~ '^[0-9.]+$' THEN (value::text)::NUMERIC
            WHEN jsonb_typeof(value::jsonb) = 'number' THEN (value::text)::NUMERIC
            WHEN (value::jsonb) ? 'value' THEN (value::jsonb->>'value')::NUMERIC
            ELSE 0.3
        END AS profit_margin
    FROM inventory."Settings"
    WHERE name = 'PROFIT_MARGIN'
    LIMIT 1
),
settings_energy AS (
    SELECT
        CASE
            WHEN settings::text ~ '^[0-9.]+$' THEN (settings::text)::NUMERIC
            WHEN jsonb_typeof(settings::jsonb) = 'number' THEN (settings::text)::NUMERIC
            WHEN (settings::jsonb) ? 'value' THEN (settings::jsonb->>'value')::NUMERIC
            ELSE 0
        END AS cost_per_kwh
    FROM "print-farm"."Settings"
    WHERE settingstype = 'COST_PER_KWH'
    LIMIT 1
),
selected_print_files AS (
    SELECT *
    FROM (
        SELECT
            pp."productId" AS product_id,
            pp.id AS product_part_id,
            pp."quantityNeeded"::NUMERIC AS quantity_needed,
            f.id AS file_id,
            f."estimatedDurationMinutes"::NUMERIC AS estimated_duration_minutes,
            f."partCount",
            f."compatiblePrinters",
            f."fileExpectsFts",
            f."nozzleMode",
            f."extruderTypes",
            fp.quantity AS file_part_quantity,
            ROW_NUMBER() OVER (
                PARTITION BY pp.id
                ORDER BY
                    CASE
                        WHEN f.status = 'APPROVED' THEN 0
                        WHEN f.status = 'DRAFT' THEN 1
                        ELSE 2
                    END,
                    f.version DESC,
                    f."updatedAt" DESC
            ) AS rn
        FROM inventory."ProductPart" pp
        JOIN inventory."ProductPartPlan" ap
          ON ap.id = pp."planId" AND ap.status = 'ACTIVE'
        JOIN "print-farm"."ProjectPart" fp
          ON fp."productPartId" = pp.id
        JOIN "print-farm"."ProjectThreeMFFile" f
          ON f.id = fp."fileId"
        WHERE pp."sourceType" = 'MAKE'
          AND f.status IN ('APPROVED', 'DRAFT')
    ) ranked
    WHERE rn = 1
),
file_material_stats AS (
    SELECT
        spf.file_id,
        COUNT(DISTINCT pfm.id) AS file_material_count,
        ARRAY_REMOVE(ARRAY_AGG(DISTINCT i."categoryId"), NULL) AS material_category_ids,
        ARRAY_REMOVE(ARRAY_AGG(DISTINCT LOWER(c.name)), NULL) AS material_category_names
    FROM selected_print_files spf
    LEFT JOIN "print-farm"."ProjectFileMaterial" pfm
      ON pfm."fileId" = spf.file_id
    LEFT JOIN inventory."Item" i
      ON i.id = pfm."materialId"
    LEFT JOIN inventory."Category" c
      ON c.id = i."categoryId"
    GROUP BY spf.file_id
),
print_file_energy AS (
    SELECT
        spf.product_id,
        spf.product_part_id,
        spf.quantity_needed,
        spf.file_id,
        (
            spf.estimated_duration_minutes
            / NULLIF(COALESCE(NULLIF(spf.file_part_quantity, 0), NULLIF(spf."partCount", 0)), 0)
        ) AS print_minutes_per_part,
        (
            LEAST(spf.estimated_duration_minutes, heat_profile.heat_minutes_per_plate)
            / NULLIF(COALESCE(NULLIF(spf.file_part_quantity, 0), NULLIF(spf."partCount", 0)), 0)
        ) AS heat_minutes_per_part,
        (
            GREATEST(spf.estimated_duration_minutes - heat_profile.heat_minutes_per_plate, 0)
            / NULLIF(COALESCE(NULLIF(spf.file_part_quantity, 0), NULLIF(spf."partCount", 0)), 0)
        ) AS run_minutes_per_part,
        COALESCE(printer_profile.avg_run_power_w, 0) AS avg_run_power_w,
        COALESCE(printer_profile.peak_power_w, 0) AS peak_power_w,
        CASE
            WHEN COALESCE(spf."fileExpectsFts", false)
              OR COALESCE(spf."nozzleMode", '') = 'DUAL'
              OR COALESCE(array_length(spf."extruderTypes", 1), 0) > 1
              OR COALESCE(fms.file_material_count, 0) > 1
            THEN COALESCE(ams_profile.ams_working_power_w, 0)
            ELSE 0
        END AS ams_working_power_w
    FROM selected_print_files spf
    LEFT JOIN file_material_stats fms
      ON fms.file_id = spf.file_id
    CROSS JOIN LATERAL (
        SELECT CASE
            -- ABS/ASA e materiali tecnici: piatto ~100 °C, circa 8 minuti.
            WHEN EXISTS (
                SELECT 1
                FROM UNNEST(COALESCE(fms.material_category_names, ARRAY[]::TEXT[])) AS category_name(name)
                WHERE category_name.name LIKE '%abs%'
                   OR category_name.name LIKE '%asa%'
                   OR category_name.name LIKE '%pc%'
                   OR category_name.name LIKE '%nylon%'
            ) THEN 8::NUMERIC
            -- PETG di solito richiede un piatto piu caldo del PLA: stima prudente.
            WHEN EXISTS (
                SELECT 1
                FROM UNNEST(COALESCE(fms.material_category_names, ARRAY[]::TEXT[])) AS category_name(name)
                WHERE category_name.name LIKE '%petg%'
            ) THEN 5::NUMERIC
            -- PLA raggiunge ~55 °C in circa 3/4 minuti; usiamo 4 minuti.
            ELSE 4::NUMERIC
        END AS heat_minutes_per_plate
    ) heat_profile
    LEFT JOIN LATERAL (
        SELECT
            AVG(
                COALESCE(
                    (
                        SELECT AVG(ep_specific."powerW"::NUMERIC)
                        FROM "print-farm"."PrinterModelEnergyProfile" ep_specific
                        WHERE ep_specific."printerModelId" = pm.id
                          AND ep_specific.voltage = 'V220'
                          AND ep_specific.phase = 'PRINT_RUN'
                          AND ep_specific."materialCategoryId" = ANY(fms.material_category_ids)
                    ),
                    ep_run_default."powerW"::NUMERIC,
                    0
                )
            ) AS avg_run_power_w,
            MAX(
                COALESCE(
                    (
                        SELECT MAX(ep_heat_specific."powerW"::NUMERIC)
                        FROM "print-farm"."PrinterModelEnergyProfile" ep_heat_specific
                        WHERE ep_heat_specific."printerModelId" = pm.id
                          AND ep_heat_specific.voltage = 'V220'
                          AND ep_heat_specific.phase = 'PRINT_HEAT'
                          AND ep_heat_specific."materialCategoryId" = ANY(fms.material_category_ids)
                    ),
                    ep_heat_default."powerW"::NUMERIC,
                    0
                )
            ) AS peak_power_w
        FROM UNNEST(spf."compatiblePrinters") AS compatible(name)
        JOIN "print-farm"."PrinterModel" pm
          ON pm.name = compatible.name
        LEFT JOIN "print-farm"."PrinterModelEnergyProfile" ep_run_default
          ON ep_run_default."printerModelId" = pm.id
         AND ep_run_default.voltage = 'V220'
         AND ep_run_default.phase = 'PRINT_RUN'
         AND ep_run_default."materialCategoryId" IS NULL
        LEFT JOIN "print-farm"."PrinterModelEnergyProfile" ep_heat_default
          ON ep_heat_default."printerModelId" = pm.id
         AND ep_heat_default.voltage = 'V220'
         AND ep_heat_default.phase = 'PRINT_HEAT'
         AND ep_heat_default."materialCategoryId" IS NULL
    ) printer_profile ON true
    LEFT JOIN LATERAL (
        SELECT COALESCE(
            AVG(aep."powerW"::NUMERIC),
            (SELECT AVG(fallback."powerW"::NUMERIC)
             FROM "print-farm"."AmsEnergyProfile" fallback
             WHERE fallback.phase = 'WORKING'),
            0
        ) AS ams_working_power_w
        FROM UNNEST(spf."compatiblePrinters") AS compatible(name)
        JOIN "print-farm"."PrinterModel" pm
          ON pm.name = compatible.name
        JOIN "print-farm"."Printer" printer
          ON printer."modelId" = pm.id
         AND COALESCE(printer.ams, false) = true
         AND printer."amsModel" IS NOT NULL
        JOIN "print-farm"."AmsEnergyProfile" aep
          ON aep."amsModel" = printer."amsModel"
         AND aep.phase = 'WORKING'
    ) ams_profile ON true
),
product_energy AS (
    SELECT
        product_id,
        SUM(COALESCE(print_minutes_per_part, 0) * quantity_needed) AS print_minutes,
        SUM(COALESCE(heat_minutes_per_part, 0) * quantity_needed) AS heat_minutes,
        SUM(COALESCE(run_minutes_per_part, 0) * quantity_needed) AS run_minutes,
        SUM(
            COALESCE(heat_minutes_per_part, 0)
            * quantity_needed
            * COALESCE(peak_power_w, 0)
            / 60000.0
        ) AS heating_energy_kwh,
        SUM(
            COALESCE(run_minutes_per_part, 0)
            * quantity_needed
            * COALESCE(avg_run_power_w, 0)
            / 60000.0
        ) AS printing_energy_kwh,
        SUM(
            (
                COALESCE(heat_minutes_per_part, 0) * COALESCE(peak_power_w, 0)
                + COALESCE(run_minutes_per_part, 0) * COALESCE(avg_run_power_w, 0)
            )
            * quantity_needed
            / 60000.0
        ) AS printer_energy_kwh,
        SUM(
            COALESCE(print_minutes_per_part, 0)
            * quantity_needed
            * COALESCE(ams_working_power_w, 0)
            / 60000.0
        ) AS ams_energy_kwh,
        AVG(NULLIF(avg_run_power_w, 0)) AS avg_run_power_w,
        MAX(NULLIF(peak_power_w, 0)) AS peak_power_w
    FROM print_file_energy
    GROUP BY product_id
)
SELECT
    p.id AS product_id,
    p.name AS product_name,

    -- Costo materie prime
    cb.materials_cost,
    cb.buy_parts_cost,
    cb.components_cost,
    cb.packaging_cost,
    cb.utilities_cost,
    cb.raw_material_cost,

    -- Metriche tempi lavoro (storico)
    COALESCE(lt.median_seconds_per_unit, 0)::DECIMAL(12,2) AS median_seconds_per_unit,
    COALESCE(lt.avg_seconds_per_unit_total, 0)::DECIMAL(12,2) AS avg_seconds_per_unit_total,
    COALESCE(lt.avg_seconds_per_unit_monthly, 0)::DECIMAL(12,2) AS avg_seconds_per_unit_monthly,
    COALESCE(lt.median_minutes_per_unit, 0)::DECIMAL(10,2) AS median_minutes_per_unit,
    COALESCE(lt.avg_minutes_per_unit_total, 0)::DECIMAL(10,2) AS avg_minutes_per_unit_total,
    COALESCE(lt.avg_minutes_per_unit_monthly, 0)::DECIMAL(10,2) AS avg_minutes_per_unit_monthly,
    COALESCE(lt.sample_size_total, 0) AS sample_size_total,
    COALESCE(lt.months_with_data, 0) AS months_with_data,

    -- FALSE = manodopera mai misurata: il costo operativo è 0 perché non esistono
    -- campioni di assemblaggio, non perché l'assemblaggio sia gratis.
    (COALESCE(lt.sample_size_total, 0) > 0) AS has_labor_data,

    -- Costo operativo (lavoro): costo/pezzo pesato per operatore, 0 senza campioni.
    CAST(blend.blended_labor_cost_per_unit AS DECIMAL(12,4)) AS operational_cost,

    -- Costo totale unitario (materie + manodopera + energia; nessuna stima spedizione)
    CAST(
        cb.raw_material_cost
        + blend.blended_labor_cost_per_unit
        + COALESCE(energy.electricity_cost, 0)
    AS DECIMAL(12,4)) AS total_cost,

    -- Prezzo suggerito base (costo totale * (1 + margine)).
    CAST(
        (
            cb.raw_material_cost
            + blend.blended_labor_cost_per_unit
            + COALESCE(energy.electricity_cost, 0)
        ) * (1 + COALESCE((SELECT profit_margin FROM settings_margin), 0.3))
    AS DECIMAL(12,2)) AS suggested_price,

    -- Prezzo manuale / effettivo
    p."sellingPrice",
    COALESCE(p."sellingPrice",
        CAST(
            (
                cb.raw_material_cost
                + blend.blended_labor_cost_per_unit
                + COALESCE(energy.electricity_cost, 0)
            ) * (1 + COALESCE((SELECT profit_margin FROM settings_margin), 0.3))
        AS DECIMAL(12,2))
    ) AS effective_selling_price,

    -- Recente (90gg), può essere NULL
    lt.recent_median_seconds_per_unit,
    lt.recent_avg_seconds_per_unit,
    lt.recent_median_minutes_per_unit,
    lt.recent_avg_minutes_per_unit,
    COALESCE(lt.recent_sample_size, 0) AS recent_sample_size,

    -- Secondi/unità usati per il costo operativo (mix graduale recente/storico)
    blend.blended_seconds_per_unit::DECIMAL(12,2) AS effective_labor_seconds_per_unit,

    -- Manodopera da mediana storica (confronto UI)
    COALESCE(lt.median_labor_cost_per_unit, 0)::DECIMAL(12,4) AS historical_operational_cost,

    -- Costo operativo da solo dato recente (NULL se recente non valido)
    CASE
        WHEN lt.recent_median_labor_cost_per_unit IS NOT NULL THEN
            lt.recent_median_labor_cost_per_unit::DECIMAL(12,4)
        ELSE NULL
    END AS recent_operational_cost,

    -- Costo produzione (materie + manodopera effettiva + energia)
    CAST(
        cb.raw_material_cost
        + blend.blended_labor_cost_per_unit
        + COALESCE(energy.electricity_cost, 0)
    AS DECIMAL(12,4)) AS production_cost,

    -- Stima energia stampa da file 3MF selezionati (APPROVED, fallback DRAFT)
    COALESCE(pe.print_minutes, 0)::DECIMAL(12,2) AS print_minutes,
    COALESCE(pe.printer_energy_kwh, 0)::DECIMAL(12,4) AS printer_energy_kwh,
    COALESCE(pe.ams_energy_kwh, 0)::DECIMAL(12,4) AS ams_energy_kwh,
    COALESCE(energy.total_energy_kwh, 0)::DECIMAL(12,4) AS total_energy_kwh,
    COALESCE(energy.electricity_cost, 0)::DECIMAL(12,4) AS electricity_cost,
    COALESCE((SELECT cost_per_kwh FROM settings_energy), 0)::DECIMAL(12,4) AS energy_cost_per_kwh,
    COALESCE(pe.avg_run_power_w, 0)::DECIMAL(12,3) AS avg_run_power_w,
    COALESCE(pe.peak_power_w, 0)::DECIMAL(12,3) AS peak_power_w,
    COALESCE(pe.heat_minutes, 0)::DECIMAL(12,2) AS heat_minutes,
    COALESCE(pe.run_minutes, 0)::DECIMAL(12,2) AS run_minutes,
    COALESCE(pe.heating_energy_kwh, 0)::DECIMAL(12,4) AS heating_energy_kwh,
    COALESCE(pe.printing_energy_kwh, 0)::DECIMAL(12,4) AS printing_energy_kwh

FROM inventory."Product" p
JOIN inventory_views.v_product_cost_breakdown cb ON cb.product_id = p.id
LEFT JOIN inventory_views.v_product_labor_time_stats lt ON lt.product_id = p.id
LEFT JOIN product_energy pe ON pe.product_id = p.id
CROSS JOIN LATERAL (
    SELECT
        CASE
            -- Nessun campione: 0, non un tempo base inventato (vedi has_labor_data).
            WHEN lt.product_id IS NULL OR COALESCE(lt.sample_size_total, 0) = 0 THEN 0::NUMERIC
            WHEN lt.recent_median_seconds_per_unit IS NULL THEN COALESCE(lt.median_seconds_per_unit, 0)::NUMERIC
            WHEN COALESCE(lt.recent_sample_size, 0) >= 10 THEN lt.recent_median_seconds_per_unit::NUMERIC
            WHEN COALESCE(lt.recent_sample_size, 0) >= 3 THEN
                (lt.recent_sample_size::NUMERIC / 10.0) * lt.recent_median_seconds_per_unit::NUMERIC
                + (1.0 - lt.recent_sample_size::NUMERIC / 10.0) * COALESCE(lt.median_seconds_per_unit, 0)::NUMERIC
            ELSE COALESCE(lt.median_seconds_per_unit, 0)::NUMERIC
        END AS blended_seconds_per_unit,
        CASE
            -- Nessun campione: costo manodopera 0 (mai misurato), niente forfait.
            WHEN lt.product_id IS NULL OR COALESCE(lt.sample_size_total, 0) = 0 THEN 0::NUMERIC
            WHEN lt.recent_median_labor_cost_per_unit IS NULL THEN COALESCE(lt.median_labor_cost_per_unit, 0)::NUMERIC
            WHEN COALESCE(lt.recent_sample_size, 0) >= 10 THEN lt.recent_median_labor_cost_per_unit::NUMERIC
            WHEN COALESCE(lt.recent_sample_size, 0) >= 3 THEN
                (lt.recent_sample_size::NUMERIC / 10.0) * lt.recent_median_labor_cost_per_unit::NUMERIC
                + (1.0 - lt.recent_sample_size::NUMERIC / 10.0) * COALESCE(lt.median_labor_cost_per_unit, 0)::NUMERIC
            ELSE COALESCE(lt.median_labor_cost_per_unit, 0)::NUMERIC
        END AS blended_labor_cost_per_unit
) blend
CROSS JOIN LATERAL (
    SELECT
        (
            COALESCE(pe.printer_energy_kwh, 0)
            + COALESCE(pe.ams_energy_kwh, 0)
        ) AS total_energy_kwh,
        (
            COALESCE(pe.printer_energy_kwh, 0)
            + COALESCE(pe.ams_energy_kwh, 0)
        ) * COALESCE((SELECT cost_per_kwh FROM settings_energy), 0) AS electricity_cost
) energy;
