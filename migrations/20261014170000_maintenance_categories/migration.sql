-- Categorie di manutenzione (14/10/2026): problemi scelti all'avvio (correggibili
-- in chiusura) e interventi scelti alla chiusura, gestiti da Impostazioni →
-- Manutenzione. Sostituiscono il testo libero come chiave di statistiche e
-- dashboard; la descrizione resta facoltativa (obbligatoria solo con «Altro»).
-- Additiva: colonne nuove nullable.
-- CreateEnum
CREATE TYPE "print-farm"."MaintenanceCategoryKind" AS ENUM ('ISSUE', 'RESOLUTION');

-- AlterTable
ALTER TABLE "print-farm"."PrinterMaintenanceLog" ADD COLUMN     "issueCategoryId" UUID,
ADD COLUMN     "issueCategorySource" TEXT;

-- CreateTable
CREATE TABLE "print-farm"."MaintenanceCategory" (
    "id" UUID NOT NULL,
    "kind" "print-farm"."MaintenanceCategoryKind" NOT NULL,
    "code" TEXT NOT NULL,
    "label" TEXT NOT NULL,
    "description" TEXT,
    "group" TEXT,
    "color" TEXT,
    "icon" TEXT,
    "keywords" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "isOther" BOOLEAN NOT NULL DEFAULT false,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "MaintenanceCategory_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "print-farm"."MaintenanceCategorySuggestion" (
    "issueCategoryId" UUID NOT NULL,
    "resolutionCategoryId" UUID NOT NULL,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "MaintenanceCategorySuggestion_pkey" PRIMARY KEY ("issueCategoryId","resolutionCategoryId")
);

-- CreateTable
CREATE TABLE "print-farm"."PrinterMaintenanceLogResolution" (
    "maintenanceLogId" UUID NOT NULL,
    "categoryId" UUID NOT NULL,
    "source" TEXT NOT NULL DEFAULT 'OPERATOR',
    "createdAt" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PrinterMaintenanceLogResolution_pkey" PRIMARY KEY ("maintenanceLogId","categoryId")
);

-- CreateIndex
CREATE INDEX "MaintenanceCategory_kind_active_sortOrder_idx" ON "print-farm"."MaintenanceCategory"("kind", "active", "sortOrder");

-- CreateIndex
CREATE UNIQUE INDEX "MaintenanceCategory_kind_code_key" ON "print-farm"."MaintenanceCategory"("kind", "code");

-- CreateIndex
CREATE INDEX "MaintenanceCategorySuggestion_resolutionCategoryId_idx" ON "print-farm"."MaintenanceCategorySuggestion"("resolutionCategoryId");

-- CreateIndex
CREATE INDEX "PrinterMaintenanceLogResolution_categoryId_idx" ON "print-farm"."PrinterMaintenanceLogResolution"("categoryId");

-- CreateIndex
CREATE INDEX "PrinterMaintenanceLog_issueCategoryId_idx" ON "print-farm"."PrinterMaintenanceLog"("issueCategoryId");

-- AddForeignKey
ALTER TABLE "print-farm"."PrinterMaintenanceLog" ADD CONSTRAINT "PrinterMaintenanceLog_issueCategoryId_fkey" FOREIGN KEY ("issueCategoryId") REFERENCES "print-farm"."MaintenanceCategory"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."MaintenanceCategorySuggestion" ADD CONSTRAINT "MaintenanceCategorySuggestion_issueCategoryId_fkey" FOREIGN KEY ("issueCategoryId") REFERENCES "print-farm"."MaintenanceCategory"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."MaintenanceCategorySuggestion" ADD CONSTRAINT "MaintenanceCategorySuggestion_resolutionCategoryId_fkey" FOREIGN KEY ("resolutionCategoryId") REFERENCES "print-farm"."MaintenanceCategory"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."PrinterMaintenanceLogResolution" ADD CONSTRAINT "PrinterMaintenanceLogResolution_maintenanceLogId_fkey" FOREIGN KEY ("maintenanceLogId") REFERENCES "print-farm"."PrinterMaintenanceLog"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "print-farm"."PrinterMaintenanceLogResolution" ADD CONSTRAINT "PrinterMaintenanceLogResolution_categoryId_fkey" FOREIGN KEY ("categoryId") REFERENCES "print-farm"."MaintenanceCategory"("id") ON DELETE RESTRICT ON UPDATE CASCADE;


-- Seed (14/10/2026): categorie iniziali ricavate dai 313 interventi registrati
-- dal 10/02 al 14/10/2026 (motivi, note di chiusura, ricambi usati) e dagli
-- errori più frequenti delle stampanti (PrinterLogs, ultimi 120 giorni). Si
-- gestiscono da Impostazioni → Manutenzione. Le parole chiave sono in
-- minuscolo e senza accenti e valgono a inizio parola
-- (`lib/maintenance/category-matcher.ts`).
INSERT INTO "print-farm"."MaintenanceCategory"
  ("id", "kind", "code", "label", "description", "group", "color", "icon", "keywords", "isOther", "sortOrder")
VALUES
  -- Problemi (ISSUE) ---------------------------------------------------------
  (gen_random_uuid(), 'ISSUE', 'filamento_incastrato', 'Filamento incastrato in testina', 'Filamento bloccato tra estrusore e ugello: non entra e non esce.', 'Filamento', 'amber', 'cable',
    ARRAY['incastr', 'incass', 'bloccat', 'in astrato', 'filamento incastr', 'filamento bloccat', 'incastrato il filamento', 'incastro filamento', 'incastro del filamento', 'sblocco filamento', 'si blocca', 'cambio del filamento', 'impossibile estrarre il filamento'], false, 10),
  (gen_random_uuid(), 'ISSUE', 'filo_spezzato_ams', 'Filo spezzato nell''AMS', 'Filamento rotto o spezzato dentro l''AMS o nel percorso verso la testina.', 'Filamento', 'violet', 'unlink',
    ARRAY['spezzat', 'filo spezzat', 'filamento spezzat', 'filamento rott', 'filo rott', 'incastrato nella ams', 'incastrato nell ams', 'nella ams', 'nell ams', 'dentro l ams', 'non e riuscito a ritirare il filamento'], false, 12),
  (gen_random_uuid(), 'ISSUE', 'filamento_non_carica', 'Il filamento non si carica', 'Il caricamento fallisce: l''AMS non spinge o l''estrusore non prende il filo.', 'Filamento', 'amber', 'arrow-down-to-line',
    ARRAY['non si carica', 'non carica', 'non si e caricat', 'caricare il filamento', 'alimentare il filamento', 'allimentare il filamento', 'impossibile alimentare', 'non e riuscito a inviare il filamento', 'tpu'], false, 14),
  (gen_random_uuid(), 'ISSUE', 'bobina_aggrovigliata', 'Bobina aggrovigliata', 'Filo accavallato sulla bobina, nodo o groviglio.', 'Filamento', 'yellow', 'shuffle',
    ARRAY['aggroviglia', 'groviglio', 'accavallat', 'nodo', 'bobina'], false, 16),
  (gen_random_uuid(), 'ISSUE', 'tubo_ptfe', 'Tubo PTFE rotto o sfilato', 'Tubicino del filamento rotto, sfilato o consumato.', 'Filamento', 'yellow', 'spline',
    ARRAY['ptfe', 'tubicino', 'tubicino filamento', 'tubicino bianco', 'tubo', 'filo bianco'], false, 18),
  (gen_random_uuid(), 'ISSUE', 'ams_guasto', 'AMS: slot, motore o sensori', 'Motore, ingranaggi, uscita o sensori dell''AMS / AMS-HT difettosi.', 'AMS', 'violet', 'boxes',
    ARRAY['ams', 'slot', 'motore di assistenza', 'uscita ams', 'ams uscita', 'hub'], false, 20),
  (gen_random_uuid(), 'ISSUE', 'estrusore_incastrato', 'Estrusore incastrato', 'Estrusore bloccato o duro, gli ingranaggi non girano.', 'Estrusore', 'orange', 'lock',
    ARRAY['estrusore incastr', 'esteusore incastr', 'estrusore bloccat', 'blocco estrusore', 'incastrato nell estrusore', 'estrusore e incastr', 'estrusore si e incastr'], false, 30),
  (gen_random_uuid(), 'ISSUE', 'estrusore_non_estrude', 'Non estrude / ingranaggi consumati', 'Stampa senza estrudere, sottoestrusione, ingranaggi o motorino dell''estrusore.', 'Estrusore', 'orange', 'cog',
    ARRAY['non estrude', 'senza estrudere', 'estrusore non', 'estrusore difett', 'estrusore destro', 'estrusore sinistro', 'ingranagg', 'motorino', 'estrazione del filamento', 'sottoestrusion'], false, 32),
  (gen_random_uuid(), 'ISSUE', 'ugello_ostruito', 'Ugello ostruito (clog)', 'Ugello o hotend intasato, il filamento non esce dall''ugello.', 'Hotend', 'red', 'circle-dot',
    ARRAY['ugello', 'clog', 'cloggat', 'occlus', 'occlugat', 'ostruit', 'intasat', 'otturat', 'oturat', 'ugello incastr', 'uggello incastr', 'lugello', 'nozzle incastr', 'ugello semibloccat', 'ugello bloccat', 'hotend ostruit', 'sostituire ugello', 'osservare l ugello'], false, 40),
  (gen_random_uuid(), 'ISSUE', 'blob', 'Blob sulla testina', 'Plastica avvolta attorno alla testina, perdite dall''heatbreak, spaghetti.', 'Hotend', 'rose', 'droplets',
    ARRAY['blob', 'nel blob', 'da blob', 'filamento ovunque', 'heatbrake', 'heatbreak', 'uscendo filamento', 'spaghetti'], false, 42),
  (gen_random_uuid(), 'ISSUE', 'ugello_danneggiato', 'Ugello fuso o danneggiato', 'Ugello sciolto, fuso, piegato o rotto.', 'Hotend', 'rose', 'flame',
    ARRAY['fuso', 'sciolt', 'ugello danneggiat', 'ugello rott', 'nozzle rott', 'nozzolo fuso'], false, 44),
  (gen_random_uuid(), 'ISSUE', 'temperatura_hotend', 'Termistore / temperatura ugello', 'Errori di temperatura dell''ugello, termistore o resistenza.', 'Hotend', 'red', 'thermometer',
    ARRAY['termistore', 'temperatura', 'sensore di temperatura', 'resistenza', 'temperatura dell ugello', 'riscaldament'], false, 46),
  (gen_random_uuid(), 'ISSUE', 'ventola_hotend', 'Ventola hotend', 'Ventola dell''hotend lenta, ferma, rumorosa o in errore.', 'Raffreddamento', 'sky', 'fan',
    ARRAY['ventola', 'ventole', 'ventola hotend', 'ventola dell hotend', 'hotend cooling fan', 'cooling fan'], false, 50),
  (gen_random_uuid(), 'ISSUE', 'ventola_altra', 'Ventola pezzo, ausiliaria o scheda', 'Ventola di raffreddamento del pezzo, ausiliaria, della scheda o della camera.', 'Raffreddamento', 'sky', 'wind',
    ARRAY['ventola pezzo', 'ventola laterale', 'ventola ausiliaria', 'ventola aux', 'ventola scheda', 'ventola camera', 'part cooling', 'aux fan'], false, 52),
  (gen_random_uuid(), 'ISSUE', 'sensore_filamento', 'Sensore filamento in testina', 'Sensore del filamento della testina rotto o che legge male.', 'Testina', 'teal', 'scan-line',
    ARRAY['sensore filamento', 'sensore del filamento', 'rilevamento filamento'], false, 60),
  (gen_random_uuid(), 'ISSUE', 'cutter', 'Cutter bloccato o rotto', 'Taglierina del filamento bloccata, rotta o sensore del taglio in errore.', 'Testina', 'teal', 'scissors',
    ARRAY['cutter', 'taglierina', 'taglio filamenti', 'taglio del filamento'], false, 62),
  (gen_random_uuid(), 'ISSUE', 'cover_testina', 'Cover testina staccata', 'Coperchio anteriore della testina caduto o staccato.', 'Testina', 'teal', 'shield',
    ARRAY['cover', 'coperchio', 'coperchio anteriore', 'testa portautensili', 'testa dell utensile'], false, 64),
  (gen_random_uuid(), 'ISSUE', 'cinghie', 'Cinghie', 'Cinghie lente, consumate o rotte.', 'Meccanica', 'slate', 'waypoints',
    ARRAY['cinghi', 'cinghia molla', 'tension'], false, 70),
  (gen_random_uuid(), 'ISSUE', 'assi_motori', 'Assi, motori e homing', 'Motori di movimento, asse Z, homing fallito, viti da lubrificare.', 'Meccanica', 'slate', 'move',
    ARRAY['asse', 'assi', 'motore', 'homing', 'vite trapezia', 'viti', 'lubrific', 'asse z'], false, 72),
  (gen_random_uuid(), 'ISSUE', 'alimentazione', 'Si spegne / alimentazione', 'Si spegne da sola, presa, pulsante o alimentatore.', 'Elettronica', 'yellow', 'power',
    ARRAY['si spegne', 'spegne', 'presa', 'alimentazione', 'pulsante', 'alimentatore'], false, 80),
  (gen_random_uuid(), 'ISSUE', 'elettronica', 'Schermo, scheda, SD o cavi', 'Schermo, scheda madre, scheda SD, cavi flat, lidar o fotocamera.', 'Elettronica', 'yellow', 'cpu',
    ARRAY['schermo', 'sd card', 'scheda sd', 'microsd', 'scheda', 'ribbon', 'cavo', 'cavi', 'lidar', 'fotocamera'], false, 82),
  (gen_random_uuid(), 'ISSUE', 'difetti_stampa', 'Difetti di stampa', 'Stampa male, strati spostati, pezzo finito a metà.', 'Qualità', 'blue', 'scan-eye',
    ARRAY['stampa male', 'stampato male', 'stampando male', 'difetti di stampa', 'errori di stampa', 'difett', 'a meta', 'print finished', 'strati', 'layer shift'], false, 90),
  (gen_random_uuid(), 'ISSUE', 'adesione_piatto', 'Pezzo staccato / piatto', 'Il pezzo si stacca, warping, problemi del piatto.', 'Qualità', 'indigo', 'layers',
    ARRAY['si stacca', 'staccat', 'piatto', 'adesione', 'warping', 'hotbed'], false, 92),
  (gen_random_uuid(), 'ISSUE', 'non_parte', 'La stampa non parte', 'La stampante non avvia la stampa, senza un guasto chiaro.', 'Avvio', 'zinc', 'circle-pause',
    ARRAY['non parte', 'non stampa', 'non ha stampato', 'non si avvia', 'file affettato', 'non e compatibile'], false, 100),
  (gen_random_uuid(), 'ISSUE', 'errore_stampante', 'Errore della stampante (HMS)', 'Errore o codice HMS che blocca la stampante, causa da capire.', 'Avvio', 'zinc', 'octagon-alert',
    ARRAY['errore', 'hms', 'codice errore', 'firmware', 'sportello'], false, 102),
  (gen_random_uuid(), 'ISSUE', 'cambio_configurazione', 'Cambio ugello o configurazione', 'Cambio voluto di diametro ugello, piatto o configurazione: non un guasto.', 'Configurazione', 'emerald', 'refresh-cw',
    ARRAY['con uno da', 'cambio ugello', 'cambio configurazione', 'cambio piatto'], false, 110),
  (gen_random_uuid(), 'ISSUE', 'manutenzione_programmata', 'Manutenzione programmata', 'Calibrazioni, pulizie e controlli periodici (anche da piano).', 'Programmata', 'emerald', 'calendar-check',
    ARRAY['calibrazion', 'calibration', 'pulizia', 'manutenzione pianificata', 'pianificat', 'controllo periodic'], false, 120),
  (gen_random_uuid(), 'ISSUE', 'altro', 'Altro', 'Nessuna delle categorie: descrivi cosa è successo.', 'Altro', 'zinc', 'help-circle',
    ARRAY[]::TEXT[], true, 1000),

  -- Interventi (RESOLUTION) --------------------------------------------------
  (gen_random_uuid(), 'RESOLUTION', 'sblocco_filamento', 'Sblocco filamento in testina', 'Rimosso il filamento incastrato in testina e ricaricato.', 'Filamento', 'amber', 'hand',
    ARRAY['sblocco filamento', 'sbloccat', 'sblocc', 'tolto l incastro', 'tolto il filamento', 'rimosso il filamento', 'filamento rimosso', 'messo il filo'], false, 10),
  (gen_random_uuid(), 'RESOLUTION', 'sblocco_ams', 'Rimosso filo spezzato dall''AMS', 'Tolto il pezzo di filo rotto da AMS, hub o tubi e ricaricato lo slot.', 'Filamento', 'violet', 'unlink',
    ARRAY['dall ams', 'nella ams', 'filo spezzato', 'pezzo di filo', 'sblocco ams', 'slot'], false, 12),
  (gen_random_uuid(), 'RESOLUTION', 'ricarica_bobina', 'Bobina districata o sostituita', 'Sistemato il groviglio o cambiata la bobina.', 'Filamento', 'yellow', 'disc',
    ARRAY['bobina', 'districat', 'groviglio', 'cambio bobina'], false, 14),
  (gen_random_uuid(), 'RESOLUTION', 'sostituzione_ptfe', 'Sostituzione tubo PTFE', 'Cambiato o riposizionato il tubo PTFE.', 'Filamento', 'yellow', 'spline',
    ARRAY['ptfe', 'tubicino', 'tubo'], false, 16),
  (gen_random_uuid(), 'RESOLUTION', 'riparazione_ams', 'Riparazione AMS', 'Motore, ingranaggi, sensori o pezzi dell''AMS / AMS-HT.', 'AMS', 'violet', 'boxes',
    ARRAY['riparazione ams', 'motore ams', 'ams'], false, 20),
  (gen_random_uuid(), 'RESOLUTION', 'pulizia_estrusore', 'Smontaggio e pulizia estrusore', 'Estrusore smontato, sbloccato e pulito senza cambiare pezzi.', 'Estrusore', 'orange', 'lock',
    ARRAY['sblocco estrusore', 'sbloccato estrusore', 'estrusore sbloccat', 'pulizia estrusore', 'smontato estrusore', 'smontaggio estrusore', 'pulizia ingranaggi'], false, 30),
  (gen_random_uuid(), 'RESOLUTION', 'sostituzione_ingranaggi', 'Sostituzione ingranaggi / tenditore', 'Cambiati ingranaggi, tenditore o leva dell''estrusore.', 'Estrusore', 'orange', 'cog',
    ARRAY['sostituzione ingranaggi', 'ingranaggio', 'ingranaggi', 'tenditore'], false, 32),
  (gen_random_uuid(), 'RESOLUTION', 'sostituzione_estrusore', 'Sostituzione estrusore o motorino', 'Cambiato l''estrusore completo o il suo motorino.', 'Estrusore', 'orange', 'package',
    ARRAY['sostituzione estrusore', 'cambio estrusore', 'estrusore nuovo', 'motorino', 'motore estrusore'], false, 34),
  (gen_random_uuid(), 'RESOLUTION', 'pulizia_ugello', 'Pulizia / sturatura ugello', 'Cold pull, ago, pulizia dell''ugello o dell''hotend.', 'Hotend', 'red', 'brush',
    ARRAY['pulizia ugello', 'pulizia nozzle', 'pulizia hotend', 'pulizia dell ugello', 'cold pull', 'sturat', 'tolto clog', 'sblocco ugello', 'ripristino del flusso'], false, 40),
  (gen_random_uuid(), 'RESOLUTION', 'rimozione_blob', 'Rimozione blob', 'Rimosso il blob dalla testina e ripulito l''hotend.', 'Hotend', 'rose', 'droplets',
    ARRAY['rimozione blob', 'tolto blob', 'tolto il blob', 'rimosso blob', 'rimosso il blob'], false, 42),
  (gen_random_uuid(), 'RESOLUTION', 'sostituzione_ugello', 'Sostituzione ugello / hotend', 'Cambiato ugello o hotend completo.', 'Hotend', 'red', 'circle-dot',
    ARRAY['sostituzione ugello', 'sostituito ugello', 'sostituire ugello', 'cambio ugello', 'cambiato ugello', 'sostituzione hotend', 'cambio hotend', 'hotend acciaio', 'hotend completo', 'hotend bambu'], false, 44),
  (gen_random_uuid(), 'RESOLUTION', 'sostituzione_termistore', 'Sostituzione termistore / resistenza', 'Cambiato termistore o resistenza ceramica.', 'Hotend', 'red', 'thermometer',
    ARRAY['termistore', 'resistenza'], false, 46),
  (gen_random_uuid(), 'RESOLUTION', 'sostituzione_ventola', 'Sostituzione ventola', 'Cambiata o pulita una ventola.', 'Raffreddamento', 'sky', 'fan',
    ARRAY['ventola', 'ventole'], false, 50),
  (gen_random_uuid(), 'RESOLUTION', 'sostituzione_sensore', 'Sostituzione sensore filamento', 'Cambiato il sensore del filamento della testina.', 'Testina', 'teal', 'scan-line',
    ARRAY['sensore'], false, 60),
  (gen_random_uuid(), 'RESOLUTION', 'riparazione_cutter', 'Sblocco o sostituzione cutter', 'Cutter sbloccato, pulito o sostituito.', 'Testina', 'teal', 'scissors',
    ARRAY['cutter', 'taglierina'], false, 62),
  (gen_random_uuid(), 'RESOLUTION', 'cover_rimontata', 'Cover testina rimontata', 'Rimesso o sostituito il coperchio della testina.', 'Testina', 'teal', 'shield',
    ARRAY['cover', 'coperchio'], false, 64),
  (gen_random_uuid(), 'RESOLUTION', 'cinghie', 'Cinghie sostituite o tensionate', 'Cinghie cambiate o rimesse in tensione.', 'Meccanica', 'slate', 'waypoints',
    ARRAY['cinghi', 'tension'], false, 70),
  (gen_random_uuid(), 'RESOLUTION', 'assi_motori', 'Assi, motori, lubrificazione', 'Motori di movimento, assi, viti lubrificate.', 'Meccanica', 'slate', 'move',
    ARRAY['motore', 'asse', 'assi', 'lubrific', 'grasso', 'vite'], false, 72),
  (gen_random_uuid(), 'RESOLUTION', 'calibrazione', 'Calibrazione', 'Calibrazione completa, livellamento piatto, vibrazioni.', 'Programmata', 'emerald', 'ruler',
    ARRAY['calibrazion', 'calibration', 'calibrat', 'livellament'], false, 80),
  (gen_random_uuid(), 'RESOLUTION', 'pulizia_piatto', 'Pulizia o cambio piatto', 'Piatto pulito, girato o sostituito.', 'Qualità', 'indigo', 'layers',
    ARRAY['piatto'], false, 82),
  (gen_random_uuid(), 'RESOLUTION', 'elettrico', 'Riparazione elettrica', 'Presa, pulsante, alimentatore, cavi o connettori.', 'Elettronica', 'yellow', 'power',
    ARRAY['presa', 'pulsante', 'cavo', 'cavi', 'connettore', 'alimentazione', 'alimentatore'], false, 90),
  (gen_random_uuid(), 'RESOLUTION', 'elettronica_sd', 'Schermo, scheda o SD', 'Schermo, scheda, cavo flat o scheda SD sistemati o sostituiti.', 'Elettronica', 'yellow', 'cpu',
    ARRAY['schermo', 'scheda', 'microsd', 'sd card', 'ribbon'], false, 92),
  (gen_random_uuid(), 'RESOLUTION', 'riavvio_firmware', 'Riavvio / firmware', 'Riavvio della stampante, aggiornamento o reset del firmware.', 'Avvio', 'zinc', 'rotate-ccw',
    ARRAY['riavvi', 'firmware', 'reset', 'spenta e riaccesa', 'aggiornament'], false, 100),
  (gen_random_uuid(), 'RESOLUTION', 'cambio_configurazione', 'Cambio configurazione', 'Montato un ugello di altro diametro o un altro piatto.', 'Configurazione', 'emerald', 'refresh-cw',
    ARRAY['con uno da', 'cambio configurazione'], false, 110),
  (gen_random_uuid(), 'RESOLUTION', 'nessun_intervento', 'Nessun guasto trovato', 'Controllata, nessun problema riscontrato o si è risolto da solo.', 'Altro', 'zinc', 'circle-check',
    ARRAY['nessun problema', 'nessun guasto', 'nessun intervento'], false, 120),
  (gen_random_uuid(), 'RESOLUTION', 'altro', 'Altro', 'Nessuna delle categorie: descrivi l''intervento nelle note.', 'Altro', 'zinc', 'help-circle',
    ARRAY[]::TEXT[], true, 1000)
ON CONFLICT ("kind", "code") DO NOTHING;

-- Interventi suggeriti per problema (curati; in chiusura vengono dopo quelli
-- più frequenti nello storico per lo stesso problema).
INSERT INTO "print-farm"."MaintenanceCategorySuggestion" ("issueCategoryId", "resolutionCategoryId", "sortOrder")
SELECT i."id", r."id", s.ord
FROM (VALUES
  ('filamento_incastrato', 'sblocco_filamento', 1),
  ('filamento_incastrato', 'pulizia_estrusore', 2),
  ('filamento_incastrato', 'pulizia_ugello', 3),
  ('filamento_incastrato', 'sostituzione_ptfe', 4),
  ('filo_spezzato_ams', 'sblocco_ams', 1),
  ('filo_spezzato_ams', 'sostituzione_ptfe', 2),
  ('filo_spezzato_ams', 'riparazione_ams', 3),
  ('filamento_non_carica', 'sblocco_filamento', 1),
  ('filamento_non_carica', 'sblocco_ams', 2),
  ('filamento_non_carica', 'pulizia_estrusore', 3),
  ('filamento_non_carica', 'sostituzione_ptfe', 4),
  ('bobina_aggrovigliata', 'ricarica_bobina', 1),
  ('bobina_aggrovigliata', 'sblocco_ams', 2),
  ('tubo_ptfe', 'sostituzione_ptfe', 1),
  ('ams_guasto', 'riparazione_ams', 1),
  ('ams_guasto', 'sblocco_ams', 2),
  ('estrusore_incastrato', 'pulizia_estrusore', 1),
  ('estrusore_incastrato', 'sostituzione_ingranaggi', 2),
  ('estrusore_incastrato', 'sostituzione_estrusore', 3),
  ('estrusore_non_estrude', 'sostituzione_ingranaggi', 1),
  ('estrusore_non_estrude', 'pulizia_estrusore', 2),
  ('estrusore_non_estrude', 'sostituzione_estrusore', 3),
  ('estrusore_non_estrude', 'pulizia_ugello', 4),
  ('ugello_ostruito', 'pulizia_ugello', 1),
  ('ugello_ostruito', 'sostituzione_ugello', 2),
  ('blob', 'rimozione_blob', 1),
  ('blob', 'pulizia_ugello', 2),
  ('blob', 'sostituzione_ugello', 3),
  ('ugello_danneggiato', 'sostituzione_ugello', 1),
  ('ugello_danneggiato', 'rimozione_blob', 2),
  ('temperatura_hotend', 'sostituzione_termistore', 1),
  ('temperatura_hotend', 'sostituzione_ugello', 2),
  ('ventola_hotend', 'sostituzione_ventola', 1),
  ('ventola_altra', 'sostituzione_ventola', 1),
  ('sensore_filamento', 'sostituzione_sensore', 1),
  ('cutter', 'riparazione_cutter', 1),
  ('cover_testina', 'cover_rimontata', 1),
  ('cinghie', 'cinghie', 1),
  ('cinghie', 'calibrazione', 2),
  ('assi_motori', 'assi_motori', 1),
  ('assi_motori', 'calibrazione', 2),
  ('alimentazione', 'elettrico', 1),
  ('alimentazione', 'riavvio_firmware', 2),
  ('elettronica', 'elettronica_sd', 1),
  ('elettronica', 'riavvio_firmware', 2),
  ('difetti_stampa', 'calibrazione', 1),
  ('difetti_stampa', 'pulizia_ugello', 2),
  ('difetti_stampa', 'sostituzione_ugello', 3),
  ('difetti_stampa', 'sostituzione_ingranaggi', 4),
  ('adesione_piatto', 'pulizia_piatto', 1),
  ('adesione_piatto', 'calibrazione', 2),
  ('non_parte', 'riavvio_firmware', 1),
  ('non_parte', 'sblocco_filamento', 2),
  ('non_parte', 'nessun_intervento', 3),
  ('errore_stampante', 'riavvio_firmware', 1),
  ('errore_stampante', 'nessun_intervento', 2),
  ('cambio_configurazione', 'cambio_configurazione', 1),
  ('cambio_configurazione', 'sostituzione_ugello', 2),
  ('manutenzione_programmata', 'calibrazione', 1),
  ('manutenzione_programmata', 'pulizia_ugello', 2),
  ('manutenzione_programmata', 'assi_motori', 3)
) AS s(issue_code, resolution_code, ord)
JOIN "print-farm"."MaintenanceCategory" i ON i."kind" = 'ISSUE' AND i."code" = s.issue_code
JOIN "print-farm"."MaintenanceCategory" r ON r."kind" = 'RESOLUTION' AND r."code" = s.resolution_code
ON CONFLICT DO NOTHING;

-- RLS: tabelle lette solo dalle app via Prisma (utente postgres).
ALTER TABLE "print-farm"."MaintenanceCategory" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "print-farm"."MaintenanceCategorySuggestion" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "print-farm"."PrinterMaintenanceLogResolution" ENABLE ROW LEVEL SECURITY;
