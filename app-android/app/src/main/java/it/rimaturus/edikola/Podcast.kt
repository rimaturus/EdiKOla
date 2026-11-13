// Il podcast di oggi: today's news told by two hosts, Giulia and Marco, in about the minutes asked for, in the
// style of NotebookLM's audio overviews. With a free Gemini API key (Google AI Studio) Gemini writes the
// conversation from today's articles; without it (or offline) EdiKOla writes a news round-up itself: the
// stories most papers cover first, topic by topic, as many as fit in the time.
// Giulia speaks with Paola's voice, Marco with Riccardo's.
package it.rimaturus.edikola

import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

object Podcast {
    const val WORDS_PER_MINUTE = 150
    val VOICE_NAMES = mapOf("it" to "Giulia", "it2" to "Marco")
    private val VOICE = listOf("it", "it2") // host 0 Giulia, 1 Marco

    data class Line(val host: Int, val text: String, val segment: Int)
    data class Script(val title: String, val segments: List<String>, val lines: List<Line>, val byGemini: Boolean)

    /** A story of the day: the same news in one or more papers */
    data class Story(val title: String, val brief: String, val text: String, val topic: String, val papers: List<String>)

    private val STOP = ("della dello delle degli dalla dalle nella nelle sulla sulle anche dopo come sono perché questo " +
        "questa quella quello oggi ecco cosa tutti tutto più ancora contro verso senza")
        .split(" ").toSet()

    private fun words(s: String) = Regex("\\p{L}{5,}").findAll(s.lowercase()).map { it.value }.filter { it !in STOP }.toSet()

    /** Today's stories, the same news from different papers together, those most papers cover first */
    fun stories(): List<Story> {
        class Item(val paper: String, val title: String, val brief: String, val text: String, val w: Set<String>)
        val items = Repo.todays().flatMap { (p, ed) ->
            ed.articles.mapNotNull { a ->
                if (p.lang == "en" && a.titleIt == null) return@mapNotNull null // not in Italian: the voices couldn't read it
                val title = a.titleIt ?: a.title
                val brief = a.briefIt ?: a.brief
                val text = if (p.lang == "en") brief else a.paragraphs.joinToString(" ").take(1500)
                Item(p.name, title, brief, text, words(title))
            }
        }
        val groups = mutableListOf<MutableList<Item>>()
        for (it in items) {
            val g = groups.firstOrNull { g ->
                val w = g.first().w
                val common = (w intersect it.w).size
                common >= 2 && common >= 0.3 * minOf(w.size, it.w.size)
            }
            if (g != null) g += it else groups += mutableListOf(it)
        }
        return groups.sortedByDescending { it.map { i -> i.paper }.distinct().size }.map { g ->
            val first = g.first()
            Story(first.title, first.brief, first.text, Topics.of(first.title, first.brief), g.map { it.paper }.distinct())
        }
    }

    private fun intro(date: String) = "Buongiorno e benvenuti al podcast di EdiKOla di $date."

    // ------------------------------------------------------------------ without Gemini

    private val OPEN = mapOf(
        "Politica" to "Cominciamo dalla politica.", "Economia e lavoro" to "Parliamo di economia e lavoro.",
        "Esteri e conflitti" to "Guardiamo fuori dall'Italia.", "Cronaca" to "Passiamo alla cronaca.",
        "Salute" to "Uno sguardo alla salute.", "Scienza e tecnologia" to "Spazio a scienza e tecnologia.",
        "Ambiente" to "Parliamo di ambiente.", "Cultura e spettacoli" to "Un po' di cultura e spettacoli.",
        "Sport" to "E ora lo sport.", Topics.OTHER to "Ancora qualche notizia.",
    )

    /** The round-up EdiKOla writes itself: one story per topic first, then the second ones, until time is up */
    fun offline(stories: List<Story>, minutes: Int): Script {
        val date = Store.dateLabel()
        val budget = minutes * WORDS_PER_MINUTE
        val byTopic = stories.groupBy { it.topic }
        val topics = Topics.names.filter { it in byTopic }.sortedByDescending { t -> byTopic.getValue(t).maxOf { it.papers.size } }
        val chosen = mutableMapOf<String, MutableList<Story>>()
        var used = 60 // intro and goodbye
        var round = 0
        var added = true
        while (added && used < budget) {
            added = false
            for (t in topics) {
                val s = byTopic.getValue(t).getOrNull(round) ?: continue
                val cost = (s.title + " " + s.brief).split(' ').size + 12
                if (used + cost > budget && chosen.isNotEmpty()) continue
                chosen.getOrPut(t) { mutableListOf() } += s
                used += cost
                added = true
            }
            round++
        }
        val segments = topics.filter { it in chosen }
        val lines = mutableListOf<Line>()
        lines += Line(0, intro(date) + " Io sono Giulia.", 0)
        lines += Line(1, "E io sono Marco. In circa $minutes minuti vi raccontiamo le notizie del giorno: " +
            segments.joinToString(", ") { it.lowercase() } + ".", 0)
        var host = 1
        segments.forEachIndexed { i, t ->
            lines += Line(host, OPEN[t] ?: "", i)
            for (s in chosen.getValue(t)) {
                host = 1 - host
                lines += Line(host, "${s.title}. ${s.brief}", i)
                if (s.papers.size > 1) {
                    lines += Line(1 - host, "Una notizia che trovate su " + s.papers.take(4).joinToString(", ") + ".", i)
                } else {
                    lines += Line(1 - host, "Lo racconta ${s.papers.first()}.", i)
                }
            }
        }
        val last = segments.size - 1
        lines += Line(0, "Per oggi è tutto. Gli articoli completi li trovate nell'Edicola.", last.coerceAtLeast(0))
        lines += Line(1, "Grazie per averci ascoltato, alla prossima puntata!", last.coerceAtLeast(0))
        return Script("Il podcast di oggi", segments.ifEmpty { listOf("Notizie") }, lines, false)
    }

    // ------------------------------------------------------------------ with Gemini

    /** Gemini writes the conversation; null with the reason when it can't (no key, offline, quota) */
    fun gemini(key: String, stories: List<Story>, minutes: Int): Pair<Script?, String?> {
        val date = Store.dateLabel()
        val words = minutes * WORDS_PER_MINUTE
        val news = StringBuilder()
        stories.forEachIndexed { i, s ->
            if (news.length > 60000) return@forEachIndexed
            news.append("[${i + 1}] ${s.papers.joinToString(", ")} | ${s.topic} | ${s.title}\n${s.text}\n\n")
        }
        val prompt = """
            Sei l'autore di un podcast di notizie in italiano: una conversazione naturale tra due conduttori, Giulia e Marco,
            nello stile delle "audio overview" di NotebookLM. Scrivi la puntata di oggi, $date, usando SOLO le notizie qui sotto:
            non inventare fatti, nomi o numeri.
            Durata: circa $minutes minuti, cioè circa $words parole in tutto. Scegli le notizie più importanti (quelle riportate
            da più giornali per prime), raggruppale per argomento, con passaggi naturali, domande, spiegazioni del contesto e
            brevi commenti tra i due; cita il giornale quando serve. Apertura breve, chiusura breve.
            Il testo sarà letto da una sintesi vocale: scrivi numeri, sigle e simboli come si pronunciano, frasi non troppo lunghe,
            niente elenchi, niente markup, niente emoji, niente didascalie o indicazioni di regia.
            Formato rigoroso: ogni battuta su una riga che comincia con "GIULIA:" oppure "MARCO:". Quando cominci un nuovo
            argomento scrivi prima una riga "## " seguita dal nome dell'argomento (poche parole).

            NOTIZIE DI OGGI (numero, giornali, argomento, titolo, testo):

            $news
        """.trimIndent()
        val body = JSONObject().put("contents", JSONArray().put(JSONObject().put("role", "user")
            .put("parts", JSONArray().put(JSONObject().put("text", prompt)))))
        var why = "risposta vuota"
        for (model in listOf("gemini-flash-latest", "gemini-flash-lite-latest")) {
            val (text, err) = call(key, model, body.toString())
            if (text != null) {
                val script = parse(text)
                if (script.lines.size >= 4) return script to null
                why = "risposta non valida"
            } else {
                why = err ?: why
                if (err != null && (err.contains("chiave") || err.contains("400"))) break
            }
        }
        return null to why
    }

    private fun call(key: String, model: String, body: String): Pair<String?, String?> {
        val c = URL("https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent")
            .openConnection() as HttpURLConnection
        return try {
            c.requestMethod = "POST"
            c.doOutput = true
            c.connectTimeout = 15000
            c.readTimeout = 180000
            c.setRequestProperty("Content-Type", "application/json")
            c.setRequestProperty("x-goog-api-key", key)
            c.outputStream.use { it.write(body.toByteArray()) }
            val code = c.responseCode
            if (code != 200) {
                val msg = c.errorStream?.use { String(it.readBytes()) }.orEmpty()
                return null to when (code) {
                    400, 401, 403 -> "chiave Gemini non valida ($code)"
                    429 -> "quota gratuita di Gemini finita per oggi"
                    else -> "Gemini ha risposto $code ${msg.take(80)}"
                }
            }
            val o = JSONObject(c.inputStream.use { String(it.readBytes()) })
            val parts = o.getJSONArray("candidates").getJSONObject(0).getJSONObject("content").getJSONArray("parts")
            val text = (0 until parts.length()).map { parts.getJSONObject(it) }
                .filter { !it.optBoolean("thought") }.joinToString("") { it.optString("text") }
            text to null
        } catch (e: Exception) {
            null to "Gemini non raggiungibile"
        } finally {
            c.disconnect()
        }
    }

    /** "## Topic" starts a segment; "GIULIA: …" / "MARCO: …" are lines; anything else continues the last line */
    fun parse(text: String): Script {
        val segments = mutableListOf<String>()
        val lines = mutableListOf<Line>()
        for (raw in text.lines()) {
            val l = raw.trim().trim('*').trim()
            if (l.isEmpty()) continue
            when {
                l.startsWith("#") -> segments += l.trimStart('#').trim()
                l.uppercase().startsWith("GIULIA:") -> lines += Line(0, l.substringAfter(':').trim().trim('*').trim(), (segments.size - 1).coerceAtLeast(0))
                l.uppercase().startsWith("MARCO:") -> lines += Line(1, l.substringAfter(':').trim().trim('*').trim(), (segments.size - 1).coerceAtLeast(0))
                lines.isNotEmpty() -> lines[lines.size - 1] = lines.last().copy(text = lines.last().text + " " + l)
            }
        }
        if (segments.isEmpty()) segments += "Notizie"
        return Script("Il podcast di oggi", segments, lines.filter { it.text.isNotBlank() }, true)
    }

    /** What the voices say: each line in pieces of a few sentences, a short pause between the hosts */
    fun chunks(s: Script): List<Testo.Chunk> {
        val out = mutableListOf<Testo.Chunk>()
        val sentence = Regex("[^.!?]+[.!?]*\\s*")
        s.lines.forEachIndexed { i, l ->
            val pieces = mutableListOf(StringBuilder())
            for (u in sentence.findAll(l.text).map { it.value }) {
                if (pieces.last().length + u.length > 500 && pieces.last().isNotEmpty()) pieces += StringBuilder()
                pieces.last().append(u)
            }
            val next = s.lines.getOrNull(i + 1)
            val ps = pieces.filter { it.isNotBlank() }
            ps.forEachIndexed { j, p ->
                val lastPiece = j == ps.size - 1
                val pause = when {
                    !lastPiece -> 0.15f
                    next == null -> 1f
                    next.segment != l.segment -> 0.9f
                    else -> 0.3f
                }
                out += Testo.Chunk(p.toString().trim(), VOICE[l.host], l.segment.coerceIn(0, s.segments.size - 1), pause)
            }
        }
        return out
    }
}
