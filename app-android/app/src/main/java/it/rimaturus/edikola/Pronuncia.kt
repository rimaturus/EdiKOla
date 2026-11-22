// English words in Italian texts, said the way an Italian says them: the Italian voice reads "Nature" as
// "natùre" by its rules; here it becomes "nèiciur" first. The words and their respellings are in
// assets/inglese.tsv, made by tools/pronuncia.py from CMUdict (only English words rare in Italian).
package it.rimaturus.edikola

object Pronuncia {
    private val map: Map<String, String> by lazy {
        Repo.app.assets.open("inglese.tsv").bufferedReader().useLines { lines ->
            lines.mapNotNull { l -> l.indexOf('\t').takeIf { it > 0 }?.let { l.substring(0, it) to l.substring(it + 1) } }.toMap()
        }
    }
    private val word = Regex("\\p{L}{3,}")

    /** The text with its English words respelled; acronyms (all capitals: NASA, USA) stay as they are */
    fun italiano(text: String): String = word.replace(text) { m ->
        val w = m.value
        if (w.length > 1 && w == w.uppercase()) w else map[w.lowercase()] ?: w
    }
}
