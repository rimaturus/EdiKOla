// Today's news as stories: the same news from different papers together, the stories most papers cover first
// (that's what "in primo piano" means), each with its topic. The topic comes from the language model when there is
// one (Llm: Gemini Nano on the phone), from keywords otherwise (Topics); the model's answers are kept, so each
// title is sorted once.
package it.rimaturus.edikola

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File

/** An article of a paper's edition */
data class Ref(val paper: Paper, val ed: Edition, val i: Int) {
    val article get() = ed.articles[i]
    /** In Italian: English articles have their title and brief translated */
    val title get() = article.titleIt ?: article.title
    val brief get() = article.briefIt ?: article.brief
    val image: File? get() = article.blocks.firstOrNull { it.kind == "img" }?.let { File(ed.dir, it.text) }
}

/** One news story: the articles about it (the first one is the one to read) and its topic */
data class Story(val refs: List<Ref>, val topic: String) {
    val main get() = refs.first()
    val papers get() = refs.map { it.paper.name }.distinct()
}

/** How Oggi shows the stories: the top one, the other big ones (told by several papers), then each topic's */
class Layout(stories: List<Story>) {
    val hero = stories.first()
    val big = stories.drop(1).filter { it.papers.size > 1 }.take(5)
    val byTopic = (stories.drop(1) - big.toSet()).groupBy { it.topic }
    val topics = Topics.names.filter { it in byTopic }
    /** the reading order: the reader's swipes and "Leggimi le notizie" follow it */
    val order = listOf(hero) + big + topics.flatMap { byTopic.getValue(it) }
}

object Notizie {
    val oggi = MutableStateFlow<List<Story>>(emptyList())
    private val file get() = File(Repo.app.filesDir, "argomenti.json")
    private var topics = JSONObject() // title -> topic, as the model said
    private val busy = Mutex()

    private val STOP = ("della dello delle degli dalla dalle nella nelle sulla sulle anche dopo come sono perché questo " +
        "questa quella quello oggi ecco cosa tutti tutto più ancora contro verso senza").split(" ").toSet()

    private fun words(s: String) = Regex("\\p{L}{5,}").findAll(s.lowercase()).map { it.value }.filter { it !in STOP }.toSet()

    private fun topicOf(r: Ref) = topics.optString(r.title).takeIf { it in Topics.names } ?: Topics.of(r.title, r.brief)

    /** Today's articles of the papers on the shelves (English ones only once translated: the voices read Italian) */
    private fun refs(): List<Ref> = Repo.todays().flatMap { (p, ed) ->
        ed.articles.indices.map { Ref(p, ed, it) }.filter { p.lang != "en" || it.article.titleIt != null }
    }

    /** Stories in order of importance: more papers first, then those higher on the papers' front pages */
    private fun build(): List<Story> {
        class G(val refs: MutableList<Ref>, val w: Set<String>)
        val groups = mutableListOf<G>()
        for (r in refs()) {
            val w = words(r.title)
            val g = groups.firstOrNull { g ->
                val common = (g.w intersect w).size
                common >= 2 && common >= 0.3 * minOf(g.w.size, w.size)
            }
            if (g != null) g.refs += r else groups += G(mutableListOf(r), w)
        }
        return groups.sortedWith(compareByDescending<G> { g -> g.refs.map { it.paper.id }.distinct().size }
            .thenBy { g -> g.refs.minOf { it.i } })
            .map { g ->
                // the article to read: an Italian one if there is, the longest
                val refs = g.refs.sortedWith(compareBy<Ref> { it.paper.lang == "en" }.thenByDescending { Extract.length(it.article.blocks) })
                Story(refs, topicOf(refs.first()))
            }
    }

    /** Builds the stories again (after an update), then lets the model sort the titles it hasn't seen */
    fun refresh() {
        Repo.scope.launch {
            withContext(Dispatchers.IO) {
                if (topics.length() == 0) topics = try { JSONObject(file.readText()) } catch (e: Exception) { JSONObject() }
            }
            oggi.value = build() // on the main thread, like every change of topics: a few dozen titles
            classify()
        }
    }

    // The model sorts the titles, 20 at a time; what it doesn't answer stays with the keywords
    private suspend fun classify() = busy.withLock {
        if (Llm.who() == null) return@withLock
        val todo = oggi.value.map { it.main.title }.filter { !topics.has(it) }
        if (todo.isEmpty()) return@withLock
        val names = Topics.names
        for (batch in todo.chunked(20)) {
            val prompt = "Classifica ogni titolo di giornale in UNA di queste categorie: " + names.joinToString(", ") + ".\n" +
                "Rispondi solo con una riga per titolo, nel formato \"numero: categoria\", senza altro testo.\n\n" +
                batch.mapIndexed { i, t -> "${i + 1}. $t" }.joinToString("\n")
            val answer = Llm.ask(prompt) ?: break
            for (m in Regex("(?m)^\\s*(\\d+)\\s*[.:)\\-]\\s*(.+)$").findAll(answer)) {
                val t = batch.getOrNull(m.groupValues[1].toInt() - 1) ?: continue
                val said = m.groupValues[2].trim().trim('*', '.', '"').lowercase()
                val name = names.firstOrNull { said.startsWith(it.lowercase()) } ?: names.firstOrNull { said.contains(it.lowercase().substringBefore(' ')) }
                if (name != null) topics.put(t, name)
            }
        }
        // keep only today's titles
        val now = oggi.value.map { it.main.title }.toSet()
        topics.keys().asSequence().toList().forEach { if (it !in now) topics.remove(it) }
        withContext(Dispatchers.IO) { file.writeText(topics.toString()) }
        oggi.value = oggi.value.map { s -> s.copy(topic = topicOf(s.main)) }
    }
}
