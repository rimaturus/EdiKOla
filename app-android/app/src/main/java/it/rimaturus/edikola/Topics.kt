// Sorts articles into broad topics for the Sommario, from words in the title and brief (Italian and English),
// as konewspaper.koplugin/knp_topics.lua. Each entry is the start of a word ("elezion" matches elezioni, elezione).
// The topic with most matching words wins; ties go to the one listed first; no match goes to "Altre notizie".
package it.rimaturus.edikola

object Topics {
    const val OTHER = "Altre notizie"
    private val TOPICS: List<Pair<String, List<String>>> = listOf(
        "Politica" to listOf(
            "governo", "parlament", "elezion", "elettor", "ministr", "partito", "partiti", "senat",
            "deputat", "premier", "meloni", "schlein", "salvini", "tajani", "sindaco", "sindaci",
            "referendum", "decreto", "quirinale", "mattarella", "opposizion", "maggioranza", "government", "parliament",
            "election", "minister", "senate", "congress", "president", "white house", "democrat", "republican",
            "labour", "tory", "voters", "campaign",
        ),
        "Economia e lavoro" to listOf(
            "econom", "borsa", "mercat", "inflazion", "banca", "banche", "tasse", "fisco",
            "lavorator", "sciopero", "prezz", "bollett", "aziend", "impres", "export", "dazi",
            "pension", "salari", "stipend", "manovra", "bilancio", "economy", "market", "stocks",
            "inflation", "bank", "taxes", "jobs", "tariff", "prices", "company", "companies",
            "trade", "wages", "budget", "investor", "bonus", "ecobonus", "affitt", "mutu",
            "euro",
        ),
        "Esteri e conflitti" to listOf(
            "guerra", "ucrain", "russi", "putin", "zelensk", "israel", "gaza", "hamas",
            "iran", "cina", "nato", "onu", "missil", "esercit", "bombard", "profugh",
            "war ", "ukrain", "russia", "kremlin", "china", "military", "troops", "ceasefire",
            "refugee", "united nations", "missile",
        ),
        "Cronaca" to listOf(
            "polizia", "carabinier", "arrest", "omicid", "uccis", "incident", "procura", "indagin",
            "processo", "tribunal", "condann", "furto", "rapina", "incendi", "vittim", "femminicid",
            "police", "arrested", "murder", "killed", "court", "trial", "crash", "shooting",
            "victim", "aggredit", "aggression", "delitto", "accoltell", "martello", "stabbed", "assault",
        ),
        "Salute" to listOf(
            "salute", "medic", "ospedal", "malatt", "tumor", "cancro", "vaccin", "virus",
            "sanit", "farmac", "pazient", "dieta", "health", "hospital", "disease", "cancer",
            "vaccine", "patients", "doctors", "diet",
        ),
        "Scienza e tecnologia" to listOf(
            "scienz", "ricerca", "ricercator", "scopert", "spazio", "nasa", "pianet", "stelle",
            "galass", "astronaut", "satellit", "fisic", "biolog", "intelligenza artificiale", "tecnolog", "smartphone",
            "apple", "google", "microsoft", "software", "internet", "robot", "science", "scientist",
            "research", "space", "planet", "galaxy", "physics", "artificial intelligence", "chatgpt", "technology",
            "telescope",
        ),
        "Ambiente" to listOf(
            "clima", "ambient", "inquin", "energia", "rinnovabil", "solare", "eolic", "emission",
            "alluvion", "siccit", "animal", "forest", "plastica", "riciclo", "climate", "environment",
            "pollution", "energy", "renewable", "solar", "emissions", "flood", "drought", "wildlife",
            "species", "ocean", "recycl", "maltempo", "tempesta", "nubifragi", "tromba d'aria", "frana",
            "terremot", "meteo", "storm", "hurricane", "earthquake",
        ),
        "Cultura e spettacoli" to listOf(
            "cultur", "mostra", "museo", "musei", "libro", "libri", "cinema", "film",
            "festival", "musica", "concerto", "teatro", "arte", "scrittor", "attor", "attric",
            "cantant", "culture", "museum", "book", "movie", "music", "concert", "theatre",
            "theater", "artist", "actor", "singer", "novel",
        ),
        "Sport" to listOf(
            "calcio", "serie a", "campionat", "partita", "allenator", "tennis", "sinner", "formula 1",
            "olimpi", "nazionale", "ciclismo", "giro d'italia", "football", "soccer", "match", "olympic",
            "league", "coach", "champions", "tournament", "world cup",
        ),
    )
    val names: List<String> = TOPICS.map { it.first } + OTHER

    private val punct = Regex("[\\p{Punct}\\s]+")

    fun of(title: String, brief: String = ""): String {
        val text = " " + "$title $brief".lowercase().replace(punct, " ") + " "
        var best = OTHER
        var bestN = 0
        for ((name, words) in TOPICS) {
            val n = words.count { text.contains(" " + it.replace(punct, " ")) }
            if (n > bestN) { best = name; bestN = n }
        }
        return best
    }
}
