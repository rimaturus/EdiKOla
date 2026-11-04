--[[--
Sorts articles into broad topics for the daily report, from words in the title and brief (Italian and English).
Each entry is the start of a word ("elezion" matches elezioni, elezione). The topic with most matching
words wins; ties go to the one listed first; no match goes to "Altre notizie".
ponytail: keyword counting, no language model (an LLM is too slow on the Kobo's single core and 256 MB);
add words here when an article lands in the wrong place.
]]

local TOPICS = {
    { "Politica", { "governo", "parlament", "elezion", "elettor", "ministr", "partito", "partiti", "senat", "deputat",
        "premier", "meloni", "schlein", "salvini", "tajani", "sindaco", "sindaci", "referendum", "decreto", "quirinale",
        "mattarella", "opposizion", "maggioranza", "government", "parliament", "election", "minister", "senate",
        "congress", "president", "white house", "democrat", "republican", "labour", "tory", "voters", "campaign" } },
    { "Economia e lavoro", { "econom", "borsa", "mercat", "inflazion", "banca", "banche", "tasse", "fisco", "lavorator",
        "sciopero", "prezz", "bollett", "aziend", "impres", "export", "dazi", "pension", "salari", "stipend",
        "manovra", "bilancio", "economy", "market", "stocks", "inflation", "bank", "taxes", "jobs", "tariff", "prices",
        "company", "companies", "trade", "wages", "budget", "investor", "bonus", "ecobonus", "affitt", "mutu", "euro" } },
    { "Esteri e conflitti", { "guerra", "ucrain", "russi", "putin", "zelensk", "israel", "gaza", "hamas", "iran", "cina",
        "nato", "onu", "missil", "esercit", "bombard", "profugh", "war ", "ukrain", "russia", "kremlin", "china",
        "military", "troops", "ceasefire", "refugee", "united nations", "missile" } },
    { "Cronaca", { "polizia", "carabinier", "arrest", "omicid", "uccis", "incident", "procura", "indagin", "processo",
        "tribunal", "condann", "furto", "rapina", "incendi", "vittim", "femminicid", "police", "arrested", "murder",
        "killed", "court", "trial", "crash", "shooting", "victim", "aggredit", "aggression", "delitto", "accoltell",
        "martello", "stabbed", "assault" } },
    { "Salute", { "salute", "medic", "ospedal", "malatt", "tumor", "cancro", "vaccin", "virus", "sanit", "farmac",
        "pazient", "dieta", "health", "hospital", "disease", "cancer", "vaccine", "patients", "doctors", "diet" } },
    { "Scienza e tecnologia", { "scienz", "ricerca", "ricercator", "scopert", "spazio", "nasa", "pianet", "stelle",
        "galass", "astronaut", "satellit", "fisic", "biolog", "intelligenza artificiale", "tecnolog", "smartphone",
        "apple", "google", "microsoft", "software", "internet", "robot", "science", "scientist", "research", "space",
        "planet", "galaxy", "physics", "artificial intelligence", "chatgpt", "technology", "telescope" } },
    { "Ambiente", { "clima", "ambient", "inquin", "energia", "rinnovabil", "solare", "eolic", "emission", "alluvion",
        "siccit", "animal", "forest", "plastica", "riciclo", "climate", "environment", "pollution", "energy", "renewable",
        "solar", "emissions", "flood", "drought", "wildlife", "species", "ocean", "recycl", "maltempo", "tempesta",
        "nubifragi", "tromba d'aria", "frana", "terremot", "meteo", "storm", "hurricane", "earthquake" } },
    { "Cultura e spettacoli", { "cultur", "mostra", "museo", "musei", "libro", "libri", "cinema", "film", "festival",
        "musica", "concerto", "teatro", "arte", "scrittor", "attor", "attric", "cantant", "culture", "museum", "book",
        "movie", "music", "concert", "theatre", "theater", "artist", "actor", "singer", "novel" } },
    { "Sport", { "calcio", "serie a", "campionat", "partita", "allenator", "tennis", "sinner", "formula 1", "olimpi",
        "nazionale", "ciclismo", "giro d'italia", "football", "soccer", "match", "olympic", "league", "coach",
        "champions", "tournament", "world cup" } },
}
local OTHER = "Altre notizie"

local M = { OTHER = OTHER, names = {} }
for _, t in ipairs(TOPICS) do table.insert(M.names, t[1]) end
table.insert(M.names, OTHER)

--- The topic name for an article
function M.of(title, brief)
    local text = " " .. (title .. " " .. (brief or "")):lower():gsub("[%p%s]+", " ") .. " "
    local best, best_n = OTHER, 0
    for _, t in ipairs(TOPICS) do
        local n = 0
        for _, w in ipairs(t[2]) do
            if text:find(" " .. w:gsub("%p", " "), 1, true) then n = n + 1 end
        end
        if n > best_n then best, best_n = t[1], n end
    end
    return best
end

return M
