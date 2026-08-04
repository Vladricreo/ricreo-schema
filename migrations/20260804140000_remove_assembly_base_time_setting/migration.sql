-- Rimuove il tempo base per pezzo dell'assemblaggio.
-- Il costo manodopera non usa più un forfait quando mancano dati storici: senza
-- campioni il costo è 0 e il prodotto risulta "mai calcolato"
-- (vedi `inventory_views.v_product_pricing_summary.has_labor_data`).
--
-- Il valore ASSEMBLY_BASE_TIME_PER_PIECE resta nell'enum `SettingsName` perché
-- eliminarlo richiederebbe di ricreare il tipo, e quindi di droppare e ricreare
-- tutte le view che dipendono da `Settings.name` (es. v_fba_inventory).

DELETE FROM "inventory"."Settings"
WHERE "name" = 'ASSEMBLY_BASE_TIME_PER_PIECE';
