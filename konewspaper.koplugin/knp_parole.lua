--[[--
Words for the puzzles (pure Lua, no KOReader: tests/giochi-test.lua runs it with plain lua5.1).

    P.rng(seed)          -> function(n): 1..n (or 0..1 with no n), the same sequence for the same seed
    P.norm(s)            -> "PERCHE": upper case A-Z, accents dropped (crossword spelling)
    P.dictionary         -> { { word =, clue = }, ... } definitions written for EdiKOla
    P.keys               -> phrases for the crucipuzzle key (proverbs and short wishes)
    P.fromNews(articles) -> { { word =, clue =, source = }, ... } from today's titles: the word is blanked
]]
local P = {}

--- Park-Miller "minimal standard" generator: exact in doubles, so LuaJIT and lua5.1 agree.
function P.rng(seed)
    local s = math.floor(math.abs(seed or 1)) % 2147483646 + 1
    return function(n)
        s = s * 16807 % 2147483647
        if n then return s % n + 1 end
        return (s - 1) / 2147483646
    end
end

function P.shuffle(t, rand)
    for i = #t, 2, -1 do
        local j = rand(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

local ACCENTS = {
    ["à"] = "A", ["á"] = "A", ["â"] = "A", ["ä"] = "A", ["À"] = "A", ["Á"] = "A",
    ["è"] = "E", ["é"] = "E", ["ê"] = "E", ["ë"] = "E", ["È"] = "E", ["É"] = "E",
    ["ì"] = "I", ["í"] = "I", ["î"] = "I", ["ï"] = "I", ["Ì"] = "I", ["Í"] = "I",
    ["ò"] = "O", ["ó"] = "O", ["ô"] = "O", ["ö"] = "O", ["Ò"] = "O", ["Ó"] = "O",
    ["ù"] = "U", ["ú"] = "U", ["û"] = "U", ["ü"] = "U", ["Ù"] = "U", ["Ú"] = "U",
    ["ç"] = "C", ["Ç"] = "C", ["ñ"] = "N", ["Ñ"] = "N",
}

function P.norm(s)
    s = s:gsub("[\195][\128-\191]", ACCENTS)
    return (s:upper():gsub("[^A-Z]", ""))
end

-- Definitions in the style of Italian puzzle magazines, written for this project.
local DICT = {
    "ACQUA", "La formula è H2O", "ALBA", "Il sorgere del giorno", "ALBERO", "Ha tronco, rami e foglie",
    "ALI", "Servono per volare", "ALPI", "Catena montuosa a nord dell'Italia", "AMICO", "Persona su cui contare",
    "ANCORA", "Si getta per fermare la nave", "ANELLO", "Si porta al dito", "ANIMA", "Lo spirito",
    "ANNO", "Dura dodici mesi", "ARCO", "Lancia le frecce", "ARENA", "Anfiteatro di Verona",
    "ARIA", "La respiriamo", "ARNO", "Fiume di Firenze", "ARTE", "Pittura, scultura e architettura",
    "ASINO", "Raglia", "ASTRO", "Corpo celeste", "ATOMO", "La particella del chimico",
    "AULA", "Stanza per le lezioni", "AURORA", "Precede il giorno", "AUTO", "Ha quattro ruote",
    "AVENA", "Cereale dei fiocchi da colazione", "BACIO", "Si dà con le labbra", "BALENA", "Il gigante dei mari",
    "BANCA", "Custodisce i risparmi", "BARCA", "Si governa con il timone", "BOCCA", "Serve per mangiare",
    "BOSCO", "Luogo pieno di alberi", "BRACE", "Resta quando la fiamma si spegne", "CAFFE", "Espresso al bar",
    "CALCIO", "Sport con pallone e porte", "CAMPO", "Ci si semina il grano", "CANE", "Il migliore amico dell'uomo",
    "CANOA", "Si spinge con la pagaia", "CANTO", "Lo intona il coro", "CARNE", "La vende il macellaio",
    "CARTA", "Si ricava dalla cellulosa", "CASA", "Dove si abita", "CASTELLO", "Ha torri e ponte levatoio",
    "CENA", "Il pasto della sera", "CERA", "Quella d'api fa le candele", "CHIAVE", "Apre la serratura",
    "CIELO", "Azzurro nelle giornate serene", "CIMA", "La vetta del monte", "CITTA", "Roma o Milano",
    "COLLE", "Piccolo rilievo", "CORO", "Canta a più voci", "CORPO", "Testa, tronco e arti",
    "CUORE", "Batte nel petto", "DADO", "Ha sei facce", "DANTE", "Scrisse la Divina Commedia",
    "DELTA", "Foce a ventaglio di un fiume", "DENTE", "Lo cura il dentista", "DIGA", "Sbarra il corso del fiume",
    "DOMENICA", "Giorno di festa della settimana", "DONNA", "Signora", "DUNA", "Collina di sabbia",
    "EDERA", "Pianta rampicante sempreverde", "ELICA", "Spinge la nave", "ERA", "Periodo storico lunghissimo",
    "ERBA", "Cresce sul prato", "ESAME", "Prova scolastica", "EST", "Dove sorge il sole",
    "ESTATE", "La stagione più calda", "ETA", "Gli anni che si hanno", "ETNA", "Vulcano siciliano",
    "FAME", "Si placa mangiando", "FARO", "Guida le navi di notte", "FATA", "Ha la bacchetta magica",
    "FESTA", "Si fa per un compleanno", "FILM", "Si guarda al cinema", "FIORE", "Sboccia in primavera",
    "FIUME", "Sfocia nel mare", "FOCA", "Mammifero dei mari freddi", "FOGLIA", "Cade in autunno",
    "FORNO", "Ci si cuoce il pane", "FRECCIA", "Si scocca con l'arco", "FUOCO", "Brucia nel camino",
    "GALILEO", "Puntò il cannocchiale verso il cielo", "GATTO", "Fa le fusa", "GELATO", "Al cono o in coppetta",
    "GENTE", "Folla di persone", "GIARDINO", "Spazio verde vicino a casa", "GIOCO", "Passatempo divertente",
    "GOL", "Rete nel calcio", "GOLA", "Fa male col raffreddore", "GRANO", "Diventa farina",
    "INVERNO", "Stagione del Natale", "ISOLA", "Terra circondata dal mare", "ITALIA", "Lo Stivale",
    "LAGO", "Quello di Garda è il più grande d'Italia", "LAMA", "Parte tagliente del coltello",
    "LANA", "Si tosa alle pecore", "LATTE", "Bevanda bianca della colazione", "LAVORO", "Occupazione retribuita",
    "LEGGE", "La approva il Parlamento", "LEONARDO", "Dipinse la Gioconda", "LEONE", "Il re della foresta",
    "LETTERA", "Si spedisce col francobollo", "LETTO", "Ci si dorme", "LIBRO", "Ha pagine e copertina",
    "LIMONE", "Agrume giallo e aspro", "LUCE", "La spegne l'interruttore", "LUNA", "Satellite della Terra",
    "MAESTRO", "Insegna alle elementari", "MANO", "Ha cinque dita", "MARCONI", "Inventò la radio",
    "MARE", "Tirreno o Adriatico", "MEDICO", "Visita i pazienti", "MELA", "Il frutto di Newton",
    "MENTE", "Sede del pensiero", "MIELE", "Lo producono le api", "MONDO", "Il pianeta e chi lo abita",
    "MONETA", "Ha testa e croce", "MONTE", "Cervino o Bianco", "MURO", "Divide due stanze",
    "MUSICA", "L'arte dei suoni", "NAPOLI", "La città del Vesuvio", "NASO", "Sta al centro del viso",
    "NATALE", "Si festeggia il 25 dicembre", "NAVE", "Solca i mari", "NEO", "Piccola macchia sulla pelle",
    "NEVE", "Cade d'inverno in fiocchi", "NIDO", "Casa degli uccelli", "NOME", "Mario o Giulia",
    "NORD", "Lo indica la bussola", "NOTA", "Do, re o mi", "NOTTE", "Il contrario del giorno",
    "NUOTO", "Sport in piscina", "NUVOLA", "Porta la pioggia", "OASI", "Verde nel deserto",
    "OCA", "Starnazza nell'aia", "OCCHIO", "Organo della vista", "OCEANO", "Atlantico o Pacifico",
    "ODE", "Componimento lirico", "OLIO", "Quello d'oliva condisce l'insalata", "OMBRA", "La proietta il sole",
    "ONDA", "Si infrange sulla riva", "ONU", "Le Nazioni Unite", "OPERA", "Quella lirica si canta",
    "ORA", "Sessanta minuti", "OROLOGIO", "Segna l'ora", "ORSO", "Va in letargo",
    "ORTO", "Ci crescono le verdure", "OSSO", "Il cane lo rosicchia", "OVEST", "Dove tramonta il sole",
    "PACE", "Il contrario della guerra", "PAESE", "Piccolo centro abitato", "PANE", "Si sforna al mattino",
    "PARCO", "Grande giardino pubblico", "PAROLA", "Unità del discorso", "PENNA", "Si scrive con lei",
    "PERLA", "Si trova nell'ostrica", "PIANO", "Il pianoforte, in breve", "PIEDE", "Calza la scarpa",
    "PIZZA", "Margherita o capricciosa", "PONTE", "Unisce le due rive", "POPOLO", "Insieme dei cittadini",
    "PORTO", "Ci attraccano le navi", "PRATO", "Distesa d'erba", "QUADERNO", "Lo usano gli scolari",
    "RADIO", "Si ascolta, non si guarda", "RAMO", "Parte dell'albero", "RANA", "Gracida nello stagno",
    "RETE", "La usa il pescatore", "RICETTA", "La segue il cuoco", "RIVA", "Il bordo del fiume",
    "ROMA", "La Città Eterna", "ROSA", "Fiore con le spine", "SALE", "Si mette nell'acqua della pasta",
    "SANGUE", "Scorre nelle vene", "SARDEGNA", "L'isola dei nuraghi", "SCI", "Sport sulla neve",
    "SCUOLA", "Ci vanno gli studenti", "SEDIA", "Ci si siede", "SERA", "Viene dopo il pomeriggio",
    "SICILIA", "La più grande isola del Mediterraneo", "SOGNO", "Si fa dormendo",
    "SOLE", "La stella del nostro sistema", "SPIGA", "Contiene i chicchi di grano", "STELLA", "Brilla di notte",
    "STORIA", "Racconta il passato", "STRADA", "Ci passano le auto", "SUD", "Opposto al nord",
    "TAVOLO", "Ci si mangia sopra", "TEATRO", "Ha palco e platea", "TELA", "La dipinge il pittore",
    "TEMPO", "Lo misura l'orologio", "TENDA", "Riparo del campeggiatore", "TENNIS", "Racchetta e pallina",
    "TERRA", "Il nostro pianeta", "TETTO", "Copre la casa", "TEVERE", "Il fiume di Roma",
    "TIGRE", "Felino a strisce", "TORRE", "Quella di Pisa pende", "TRENO", "Corre sui binari",
    "UFFICIO", "Luogo di lavoro con scrivanie", "UOVO", "Lo depone la gallina", "UVA", "Si vendemmia",
    "VASO", "Contiene i fiori", "VELA", "La gonfia il vento", "VENEZIA", "La città dei canali",
    "VENTO", "Maestrale o scirocco", "VERDE", "Il colore del prato", "VERDI", "Compose l'Aida",
    "VIAGGIO", "Si prepara con la valigia", "VINO", "Rosso, bianco o rosato", "VIOLA", "Fiore o colore",
    "VOCE", "Si usa per parlare", "VULCANO", "Erutta lava", "ZAINO", "Si porta sulle spalle",
    "ZEBRA", "Cavallo a strisce", "ZUCCA", "Simbolo di Halloween",
}
P.dictionary = {}
for i = 1, #DICT, 2 do table.insert(P.dictionary, { word = DICT[i], clue = DICT[i + 1] }) end

-- Crucipuzzle keys: the letters left over in the grid spell one of these
P.keys = {
    "EVVIVA", "GRAZIE", "EDICOLA", "BEN FATTO", "CHE BELLO", "SETTIMANA", "CHI CERCA TROVA",
    "BRAVISSIMO", "COMPLIMENTI", "ENIGMISTICA", "ALLA PROSSIMA", "OTTIMO LAVORO", "BUONA LETTURA",
    "CHIAVE SVELATA", "BUONA GIORNATA", "LEGGERE FA BENE", "PAROLA NASCOSTA", "PIOVE SUL BAGNATO",
    "CHI LA DURA LA VINCE", "SBAGLIANDO S IMPARA", "MEGLIO TARDI CHE MAI", "NEL DUBBIO ASTIENITI",
    "IL TEMPO E DENARO", "LA FORTUNA E CIECA", "CHI TACE ACCONSENTE", "VIVI E LASCIA VIVERE",
    "BUON SANGUE NON MENTE", "APRILE DOLCE DORMIRE", "OGNI LASCIATA E PERSA", "L UNIONE FA LA FORZA",
    "IL SILENZIO E D ORO", "CHI FA DA SE FA PER TRE", "CAN CHE ABBAIA NON MORDE", "L ABITO NON FA IL MONACO",
    "CHI DORME NON PIGLIA PESCI", "NON CE ROSA SENZA SPINE", "L APPETITO VIEN MANGIANDO",
    "ACQUA PASSATA NON MACINA PIU", "MOGLIE E BUOI DEI PAESI TUOI", "TUTTE LE STRADE PORTANO A ROMA",
    "ROMA NON FU FATTA IN UN GIORNO", "BATTI IL FERRO FINCHE E CALDO", "PRIMA IL DOVERE POI IL PIACERE",
    "ROSSO DI SERA BEL TEMPO SI SPERA", "PAESE CHE VAI USANZA CHE TROVI", "CHI HA TEMPO NON ASPETTI TEMPO",
    "IMPARA L ARTE E METTILA DA PARTE", "OCCHIO NON VEDE CUORE NON DUOLE", "CHI VA PIANO VA SANO E VA LONTANO",
    "CHI TROVA UN AMICO TROVA UN TESORO", "NON TUTTO IL MALE VIEN PER NUOCERE",
    "CHI SEMINA VENTO RACCOGLIE TEMPESTA", "A CAVAL DONATO NON SI GUARDA IN BOCCA",
    "NATALE CON I TUOI PASQUA CON CHI VUOI", "DIMMI CON CHI VAI E TI DIRO CHI SEI",
    "CHI BEN COMINCIA E A META DELL OPERA", "TRA IL DIRE E IL FARE CE DI MEZZO IL MARE",
}

-- Words too common to make a puzzle answer out of a headline
local STOP = {}
for w in ([[ALLA ALLE AGLI ANCHE ANCORA ASSAI AVERE AVEVA BENE COME CONTRO COSA COSI CUI DALLA DALLE DAGLI
DELLA DELLE DEGLI DENTRO DOPO DOVE DUNQUE ERANO ESSERE FINO FRA GIA HANNO INFATTI INTANTO INVECE LORO MENTRE
MOLTO MOLTI MOLTE NELLA NELLE NEGLI NOSTRO NOSTRA NULLA OGNI OGGI OLTRE ORMAI PERCHE PERO POCO POI POSSO
PRIMA PRIMO PROPRIO QUALE QUALI QUANDO QUANTO QUASI QUELLA QUELLE QUELLI QUELLO QUESTA QUESTE QUESTI QUESTO
SECONDO SEMPRE SENZA SIAMO SOLO SONO SOPRA SOTTO STATA STATI STATO SULLA SULLE SUGLI SUOI TANTO TRA TUTTA
TUTTE TUTTI TUTTO VERSO VIENE ECCO ESSERCI FARE FATTO DETTO DICE DIRE VUOLE NUOVO NUOVA NUOVI NUOVE
GRANDE GRANDI ALTRO ALTRA ALTRI ALTRE ANNI ORE SETTIMANA OGGI IERI DOMANI ARRIVA ARRIVANO
WITH FROM THAT THIS THEY THEIR HAVE WILL BEEN WERE WHAT WHEN WHERE WHICH AFTER ABOUT INTO OVER MORE THAN]]):gmatch("%a+") do
    STOP[w] = true
end

--- Puzzle words out of today's headlines; the clue is the headline with the word blanked out.
-- articles: { { title =, paper = } }. One word per headline (its longest usable one), no repeats.
-- Only words whose letters are all plain or accented Latin letters, so the blank hides exactly them.
function P.fromNews(articles, max_len)
    max_len = max_len or 11
    local out, seen = {}, {}
    for _, a in ipairs(articles or {}) do
        local title = a.title or ""
        local best, best_tok
        -- tokens end at spaces, ASCII punctuation and apostrophes (straight or curly)
        for tok in title:gsub("\226\128[\152\153]", " "):gmatch("[^%s%p]+") do
            local w = P.norm(tok)
            local chars = #tok:gsub("[\195][\128-\191]", "x") -- an accented letter counts once
            if #w >= 4 and #w <= max_len and #w == chars and not STOP[w] and not seen[w]
                and (not best or #w > #best) then
                best, best_tok = w, tok
            end
        end
        if best then
            seen[best] = true
            local s, e = title:find(best_tok, 1, true)
            table.insert(out, { word = best, clue = title:sub(1, s - 1) .. "..." .. title:sub(e + 1), source = a.paper })
        end
    end
    return out
end

return P
