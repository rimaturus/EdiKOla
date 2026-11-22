// Radio EdiKOla: today's news as a radio show. The jingle, Giulia and Marco open the show, then one story at a
// time they talk it through (questions, context, a comment), a short jingle when a new section starts, the
// goodbye and the jingle again. The language model (Llm: Gemini Nano on the phone) writes each story while the
// one before is on air, so the show starts in seconds; whatever it can't write (no model, EdiKOla in the
// background) EdiKOla writes from templates, and the show goes on. Only facts from the articles.
// Giulia speaks with Paola's voice, Marco with Riccardo's.
package it.rimaturus.edikola

import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch

object Radio {
    const val TITLE = "Radio EdiKOla"
    val VOICE_NAMES = mapOf("it" to "Giulia", "it2" to "Marco")
    private val VOICE = listOf("it", "it2") // host 0 Giulia, 1 Marco
    private val NAMES = listOf("Giulia", "Marco")

    /** "Giulia e Marco preparano la notizia 3 di 8" while the show is being written */
    val status = MutableStateFlow<String?>(null)
    private var job: Job? = null

    private class Line(val host: Int, val text: String)

    private const val HOSTS = "Radio EdiKOla è un programma radiofonico di notizie in italiano, in diretta. Lo conducono " +
        "Giulia, curiosa e calda, che fa le domande che farebbe chi ascolta, e Marco, preciso, che spiega il contesto con " +
        "un filo di ironia. Parlano tra loro in modo naturale e spontaneo, come due amici in radio."
    private const val RULES = "Regole: usa solo i fatti scritti qui, non inventare nomi, numeri, date o citazioni. Frasi " +
        "brevi, da dire ad alta voce. Niente elenchi, emoji, titoli o indicazioni di regia. Ogni riga comincia con " +
        "\"GIULIA:\" oppure \"MARCO:\"."

    /** The stories that fit in the minutes: the top one, then the best of each topic in turn; grouped by topic */
    private fun plan(stories: List<Story>, minutes: Int, smart: Boolean): List<Story> {
        val n = ((minutes * 150 - 150) / (if (smart) 130 else 70)).coerceIn(2, stories.size)
        val byTopic = stories.drop(1).groupBy { it.topic } // topics in order of their best story
        val chosen = mutableListOf(stories.first())
        var round = 0
        while (chosen.size < n) {
            val take = byTopic.values.mapNotNull { it.getOrNull(round) }.take(n - chosen.size)
            if (take.isEmpty()) break
            chosen += take
            round++
        }
        // the top story opens; then its topic goes on, and the other topics in order of their best story
        val order = chosen.map { it.topic }.distinct()
        return listOf(chosen.first()) + chosen.drop(1).sortedBy { order.indexOf(it.topic) }
    }

    /** Starts the show of the given length */
    fun start(minutes: Int) {
        job?.cancel()
        val stories = Notizie.oggi.value
        if (stories.isEmpty()) { Repo.message.value = "Ancora nessuna notizia di oggi: aggiorna prima i giornali."; return }
        Ascolta.startRadio(TITLE)
        job = Repo.scope.launch {
            val smart = Llm.who() != null
            val chosen = plan(stories, minutes, smart)
            val date = Store.dateLabel()
            fun on() = Ascolta.state.value?.radio == true // stopped: stop writing too
            Ascolta.add("Sigla", listOf(Testo.Chunk("", "", 0, 0.2f, "sigla")))

            status.value = "Giulia e Marco si preparano"
            val heads = chosen.take(3).joinToString("; ") { it.main.title }
            val intro = write("$HOSTS\nScrivi l'apertura della puntata di oggi, $date: salutano chi ascolta, si presentano con " +
                "una battuta spontanea e anticipano in poche parole le notizie principali: $heads. Da 4 a 6 battute.\n$RULES")
                ?: listOf(Line(0, "Buongiorno e benvenuti a Radio EdiKOla, oggi è $date. Io sono Giulia."),
                    Line(1, "E io sono Marco. Oggi parliamo di " + chosen.map { it.topic.lowercase() }.distinct()
                        .filter { it != Topics.OTHER.lowercase() }.joinToString(", ").ifEmpty { "tante cose" } +
                        ". Si comincia dalla notizia di cui parlano più giornali."))
            if (!on()) return@launch
            Ascolta.add("Apertura", pieces(intro))

            var last: String? = null
            for ((i, s) in chosen.withIndex()) {
                status.value = "Giulia e Marco preparano la notizia ${i + 1} di ${chosen.size}"
                val lead = i % 2
                val where = when {
                    i == 0 -> "È la notizia d'apertura: quella di cui parlano più giornali."
                    s.topic != last -> "Comincia la parte dedicata a: ${s.topic.lowercase()}."
                    else -> "Si resta in tema: ${s.topic.lowercase()}."
                }
                val r = s.main
                val text = r.article.paragraphs.joinToString(" ").take(1500).let { if (r.paper.lang == "en") r.brief else it }
                val lines = write("$HOSTS\n$where Comincia a parlare ${NAMES[lead]}. Raccontano questa notizia, riportata da " +
                    "${s.papers.joinToString(", ")}.\nTITOLO: ${r.title}\nTESTO: $text\n\nScrivi questo pezzo del programma: " +
                    "da 6 a 10 battute, un botta e risposta con domande, spiegazioni e un breve commento finale.\n$RULES")
                    ?: offline(s, i, s.topic != last, lead)
                if (!on()) return@launch
                val p = pieces(lines)
                Ascolta.add(r.title, if (i > 0 && s.topic != last) listOf(Testo.Chunk("", "", 0, 0.3f, "stacco")) + p else p)
                last = s.topic
            }

            status.value = "Giulia e Marco salutano"
            val bye = write("$HOSTS\nScrivi la chiusura della puntata: Giulia e Marco ringraziano chi ha ascoltato, salutano e " +
                "ricordano che gli articoli completi sono nell'app EdiKOla. Da 2 a 4 battute.\n$RULES")
                ?: listOf(Line(0, "Per oggi è tutto. Gli articoli completi li trovate in EdiKOla."),
                    Line(1, "Grazie per averci ascoltato. A domani, su Radio EdiKOla!"))
            if (!on()) return@launch
            Ascolta.add("Saluti", pieces(bye) + Testo.Chunk("", "", 0, 1f, "sigla"))
            Ascolta.done()
        }.also { it.invokeOnCompletion { status.value = null } }
    }

    private val ASK = listOf("E cosa sappiamo?", "Raccontaci.", "Cioè? Cos'è successo?", "Spiegaci meglio.", "E quindi?")
    private val NEXT = listOf("E poi c'è questa:", "Restiamo in tema.", "Un'altra notizia:", "Andiamo avanti.")
    private val OPEN = mapOf(
        "Politica" to "Parliamo di politica.", "Economia e lavoro" to "Passiamo a economia e lavoro.",
        "Esteri e conflitti" to "Guardiamo fuori dall'Italia.", "Cronaca" to "Passiamo alla cronaca.",
        "Salute" to "Uno sguardo alla salute.", "Scienza e tecnologia" to "Spazio a scienza e tecnologia.",
        "Ambiente" to "Parliamo di ambiente.", "Cultura e spettacoli" to "Un po' di cultura e spettacoli.",
        "Sport" to "E ora lo sport.", Topics.OTHER to "Ancora qualche notizia.",
    )

    /** A story without the model */
    private fun offline(s: Story, i: Int, newTopic: Boolean, lead: Int): List<Line> {
        val opener = when {
            i == 0 -> "La notizia di cui parlano più giornali oggi:"
            newTopic -> OPEN[s.topic] ?: ""
            else -> NEXT[i % NEXT.size]
        }
        val r = s.main
        return listOf(
            Line(lead, "$opener ${r.title}."),
            Line(1 - lead, ASK[i % ASK.size]),
            Line(lead, r.brief),
            Line(1 - lead, if (s.papers.size > 1) "Ne parlano ${s.papers.take(4).joinToString(", ")}." else "Lo racconta ${s.papers.first()}."),
        )
    }

    /** The model's lines, or null when there is no model or its answer isn't usable */
    private suspend fun write(prompt: String): List<Line>? {
        val text = Llm.ask(prompt) ?: return null
        val lines = mutableListOf<Line>()
        for (raw in text.lines()) {
            val l = raw.replace("*", "").replace(Regex("\\([^)]*\\)|\\[[^]]*]"), "").trim()
            if (l.isEmpty() || l.startsWith("#")) continue
            val host = NAMES.indexOfFirst { l.uppercase().startsWith(it.uppercase() + ":") }
            when {
                host >= 0 -> lines += Line(host, l.substringAfter(':').trim())
                lines.isNotEmpty() -> lines[lines.size - 1] = Line(lines.last().host, lines.last().text + " " + l)
            }
        }
        return lines.filter { it.text.isNotBlank() }.takeIf { it.size >= 2 }
    }

    /** What the voices say: each line in pieces of a few sentences, short pauses between the hosts */
    private fun pieces(lines: List<Line>): List<Testo.Chunk> {
        val out = mutableListOf<Testo.Chunk>()
        val sentence = Regex("[^.!?]+[.!?]*\\s*")
        lines.forEachIndexed { i, l ->
            val ps = mutableListOf(StringBuilder())
            for (u in sentence.findAll(l.text).map { it.value }) {
                if (ps.last().length + u.length > 400 && ps.last().isNotEmpty()) ps += StringBuilder()
                ps.last().append(u)
            }
            val parts = ps.filter { it.isNotBlank() }
            parts.forEachIndexed { j, p ->
                val pause = if (j < parts.size - 1) 0.15f else if (i == lines.size - 1) 0.8f else 0.3f
                out += Testo.Chunk(p.toString().trim(), VOICE[l.host], 0, pause)
            }
        }
        return out
    }
}
