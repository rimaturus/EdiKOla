// The app's state: which papers are on the shelves, their latest editions, the download in progress.
package it.rimaturus.edikola

import android.app.Application
import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import java.io.File

class EdikolaApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Repo.init(this)
    }
}

object Repo {
    lateinit var app: Context
    private lateinit var prefs: SharedPreferences
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    val selected = MutableStateFlow<Set<String>>(emptySet())
    val editions = MutableStateFlow<Map<String, Edition>>(emptyMap())
    /** "Scarico 3 di 25…" while updating, null otherwise */
    val progress = MutableStateFlow<String?>(null)
    val message = MutableStateFlow<String?>(null)
    val fontSize = MutableStateFlow(19)

    fun init(ctx: Context) {
        app = ctx.applicationContext
        prefs = app.getSharedPreferences("edikola", Context.MODE_PRIVATE)
        Store.root = File(app.filesDir, "edicola").apply { mkdirs() }
        selected.value = prefs.getStringSet("selected", null) ?: PAPERS.filter { it.default }.map { it.id }.toSet()
        fontSize.value = prefs.getInt("font", 19)
        scope.launch(Dispatchers.IO) {
            editions.value = PAPERS.mapNotNull { p -> Store.latest(p)?.let { p.id to it } }.toMap()
        }
    }

    fun paper(id: String) = PAPERS.first { it.id == id }
    fun shelf(section: String) = PAPERS.filter { it.section == section && it.id in selected.value }

    fun toggle(id: String) {
        val s = selected.value.toMutableSet()
        if (!s.remove(id)) s += id
        selected.value = s
        prefs.edit().putStringSet("selected", s).apply()
    }

    fun setFont(size: Int) {
        fontSize.value = size.coerceIn(14, 32)
        prefs.edit().putInt("font", fontSize.value).apply()
    }

    fun position(doc: String): Pair<Int, Int> = prefs.getInt("sec:$doc", 0) to prefs.getInt("pos:$doc", 0)
    fun savePosition(doc: String, section: Int, item: Int) {
        prefs.edit().putInt("sec:$doc", section).putInt("pos:$doc", item).apply()
    }

    /** Downloads the given papers (6 at a time); done() after, on the main thread */
    fun update(papers: List<Paper>, done: () -> Unit = {}) {
        if (progress.value != null || papers.isEmpty()) return
        progress.value = "Scarico i giornali…"
        scope.launch {
            var n = 0
            val failed = mutableListOf<String>()
            val gate = Semaphore(6)
            papers.map { p ->
                async(Dispatchers.IO) {
                    gate.withPermit {
                        val (ed, err) = try { Store.build(p) } catch (e: Exception) { null to (e.message ?: "errore") }
                        synchronized(this@Repo) {
                            n++
                            if (ed != null) editions.value = editions.value + (p.id to ed) else failed += "${p.name}: $err"
                            progress.value = "Scaricati $n di ${papers.size}"
                        }
                    }
                }
            }.awaitAll()
            progress.value = null
            if (failed.isNotEmpty()) message.value = "Non aggiornati: " + failed.joinToString("; ")
            done()
        }
    }

    /** Today's articles of the papers on the shelves, for the Sommario and the crossword */
    fun todays(): List<Pair<Paper, Edition>> {
        val today = Store.today()
        return PAPERS.filter { it.id in selected.value }.mapNotNull { p -> editions.value[p.id]?.takeIf { it.date == today }?.let { p to it } }
    }
}
