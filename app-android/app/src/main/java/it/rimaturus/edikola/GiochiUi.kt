// La Settimana di EdiKOla: the day's crossword (clues from the headlines), the crucipuzzle, three sudoku.
// Like on a paper magazine: the grid and the clues, and you write on the grid with the pen (or a finger). What you
// write stays a stroke: nothing is recognized, nothing is checked, there are no solutions.
// Puzzles are made on the phone, offline, and kept (files/giochi.json) with their ink, until "Nuovo".
package it.rimaturus.edikola

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** Saved puzzles, by key: "cruciverba", "crucipuzzle", "sudoku1".."sudoku3"; each has an "id" for its ink */
object GiochiStore {
    private val file get() = File(Repo.app.filesDir, "giochi.json")
    private fun all(): JSONObject = try { JSONObject(file.readText()) } catch (e: Exception) { JSONObject() }
    fun get(key: String): JSONObject? = all().optJSONObject(key)
    fun put(key: String, o: JSONObject) { file.writeText(all().put(key, o).toString()) }
    fun seedOfToday(): Long = Store.today().replace("-", "").toLong()
    fun ink(key: String, o: JSONObject) = "gioco_${key}_" + o.optString("id", "0")
}

private fun JSONArray.strings() = (0 until length()).map { getString(it) }
private fun JSONArray.objects() = (0 until length()).map { getJSONObject(it) }

val LEVELS = listOf("facile", "medio", "difficile")

private val GAMES = listOf(
    Triple("cruciverba", "Cruciverba del giorno", "Schema libero: molte definizioni sono i titoli di oggi, con una parola tolta."),
    Triple("crucipuzzle", "Crucipuzzle", "Cerchia le parole nello schema: le lettere che restano formano la chiave."),
    Triple("sudoku1", "Sudoku facile", "Ogni riga, colonna e riquadro con i numeri da 1 a 9."),
    Triple("sudoku2", "Sudoku medio", "Qualche numero in meno."),
    Triple("sudoku3", "Sudoku difficile", "Per chi ha tempo."),
)

@Composable
private fun toneOf(key: String): Tone {
    val pal = LocalPalette.current
    return when (key) { "cruciverba" -> pal.cruciverba; "crucipuzzle" -> pal.crucipuzzle; else -> pal.sudoku }
}

@Composable
fun GiochiCover() {
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(start = 18.dp, end = 18.dp, bottom = 24.dp)) {
        items(GAMES) { (key, title, text) ->
            val tone = toneOf(key)
            Row(Modifier.fillMaxWidth().clickable { Nav.go(Screen.Game(key)) }.padding(vertical = 16.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(width = 4.dp, height = 44.dp).background(tone.strong, RoundedCornerShape(2.dp)))
                Spacer(Modifier.width(14.dp))
                Column(Modifier.weight(1f)) {
                    Text(title, fontFamily = Display, fontWeight = FontWeight.Bold, fontSize = 21.sp, color = tone.strong)
                    Text(text, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
        }
    }
}

/** A new puzzle: today's (the first time) or another one */
private fun make(key: String, fresh: Boolean): JSONObject? {
    val seed = if (fresh) System.currentTimeMillis() % 100000000 else GiochiStore.seedOfToday()
    val o = when {
        key.startsWith("sudoku") -> {
            val level = key.last().digitToInt()
            JSONObject().put("puz", Sudoku.generate(seed * 10 + level, level).first)
        }
        key == "cruciverba" -> {
            val cw = Cruciverba.generate(Parole.fromNews(todaysHeadlines(), 11), Parole.dictionary, seed)
            JSONObject().put("rows", JSONArray(cw.rows)).put("words", JSONArray().apply {
                cw.words.forEach { w -> put(JSONObject().put("word", w.word).put("clue", w.clue).put("source", w.source ?: "")
                    .put("x", w.x).put("y", w.y).put("a", w.across).put("num", w.num)) }
            })
        }
        else -> {
            val pool = Parole.fromNews(todaysHeadlines(), 10) + Parole.dictionary
            val p = (0..5).firstNotNullOfOrNull { Crucipuzzle.generate(pool, seed + it) } ?: return null
            JSONObject().put("rows", JSONArray(p.rows)).put("key", p.key).put("words", JSONArray(p.words.map { it.word }.sorted()))
        }
    }
    return o.put("id", seed.toString())
}

private fun todaysHeadlines() = Repo.todays().flatMap { (p, ed) -> ed.articles.map { Parole.Headline(it.title, p.name) } }
    .filter { Testo.lang(it.title) == "it" }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GameScreen(which: String) {
    val tone = toneOf(which)
    val title = GAMES.first { it.first == which }.second
    var st by remember { mutableStateOf<JSONObject?>(null) }
    var renew by remember { mutableIntStateOf(0) }
    var ask by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(renew) {
        InkDoc.rubber.value = false
        val old = GiochiStore.get(which)
        // a saved one of older versions (no "id") is replaced by a new one
        st = (if (renew == 0 && old?.has("id") == true) old else null) ?: withContext(Dispatchers.Default) { make(which, renew > 0) }?.also {
            if (old?.has("id") == true) InkDoc.delete(GiochiStore.ink(which, old))
            GiochiStore.put(which, it)
        }
    }
    val s = st
    val ink = remember(s) { s?.let { InkDoc.open(GiochiStore.ink(which, it)) } }
    Scaffold(topBar = {
        TopAppBar(title = { Text(title, color = tone.strong, fontFamily = Display, fontWeight = FontWeight.Bold) },
            navigationIcon = { IconButton(onClick = { Nav.back() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Indietro") } },
            actions = { TextButton(onClick = { ask = "nuovo" }) { Text("Nuovo") } })
    }) { pad ->
        Column(Modifier.padding(pad).padding(horizontal = 12.dp)) {
            if (s == null || ink == null) {
                Text(if (which == "cruciverba") "Preparo lo schema con le notizie di oggi…" else "Preparo lo schema…", Modifier.padding(12.dp))
                return@Column
            }
            when {
                which.startsWith("sudoku") -> {
                    val puz = s.getString("puz")
                    Board(9, 9, ink, thick = 3, letter = { c, r -> puz[r * 9 + c].takeIf { it != '0' }?.toString() })
                    Tools(ink) { ask = "cancella" }
                }
                which == "cruciverba" -> {
                    val rows = s.getJSONArray("rows").strings()
                    val words = s.getJSONArray("words").objects()
                    val nums = words.associate { (it.getInt("y") * 100 + it.getInt("x")) to it.getInt("num").toString() }
                    Board(rows[0].length, rows.size, ink, black = { c, r -> rows[r][c] == '.' }, num = { c, r -> nums[r * 100 + c] })
                    Tools(ink) { ask = "cancella" }
                    LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(bottom = 16.dp)) {
                        for (across in listOf(true, false)) {
                            item { Kicker(if (across) "Orizzontali" else "Verticali", tone.strong, Modifier.padding(top = 12.dp, bottom = 4.dp)) }
                            items(words.filter { it.getBoolean("a") == across }) { w ->
                                Row(Modifier.padding(vertical = 4.dp)) {
                                    Text("${w.getInt("num")}", Modifier.width(30.dp), fontWeight = FontWeight.Bold, color = tone.strong)
                                    Text("${w.getString("clue")} (${w.getString("word").length})", Modifier.weight(1f), fontFamily = Reading)
                                }
                            }
                        }
                    }
                }
                else -> {
                    val rows = s.getJSONArray("rows").strings()
                    Board(rows[0].length, rows.size, ink, letter = { c, r -> rows[r][c].toString() })
                    Tools(ink) { ask = "cancella" }
                    LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(bottom = 16.dp)) {
                        item {
                            Text("La chiave: ${s.getString("key").length} lettere", Modifier.padding(vertical = 8.dp),
                                color = tone.strong, fontWeight = FontWeight.Bold)
                        }
                        items(s.getJSONArray("words").strings().chunked(3)) { row ->
                            Row(Modifier.padding(vertical = 3.dp)) {
                                for (w in row) Text(w, Modifier.weight(1f), fontFamily = Reading, fontWeight = FontWeight.SemiBold)
                                repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
                            }
                        }
                    }
                }
            }
        }
    }
    ask?.let { what ->
        AlertDialog(onDismissRequest = { ask = null },
            title = { Text(if (what == "nuovo") "Nuovo schema?" else "Cancellare tutto?") },
            text = { Text(if (what == "nuovo") "Lo schema di adesso e quello che ci hai scritto si perdono." else "Tutto quello che hai scritto sullo schema.") },
            confirmButton = { TextButton(onClick = { ask = null; if (what == "nuovo") renew++ else ink?.clear() }) {
                Text(if (what == "nuovo") "Nuovo" else "Cancella") } },
            dismissButton = { TextButton(onClick = { ask = null }) { Text("Annulla") } })
    }
}

/** Pen or eraser (the stylus's own eraser always works), undo, clear */
@Composable
private fun Tools(ink: InkDoc, clear: () -> Unit) {
    var rubber by InkDoc.rubber
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        FilterChip(selected = !rubber, onClick = { rubber = false }, label = { Text("Penna") })
        Spacer(Modifier.width(8.dp))
        FilterChip(selected = rubber, onClick = { rubber = true }, label = { Text("Gomma") })
        Spacer(Modifier.weight(1f))
        TextButton(onClick = { ink.undo() }) { Text("Annulla") }
        TextButton(onClick = clear) { Text("Cancella") }
    }
}

/** The grid, drawn like on paper: black squares, numbers, given letters or digits; the ink on top */
@Composable
private fun Board(cols: Int, rows: Int, ink: InkDoc, thick: Int = 0, black: (Int, Int) -> Boolean = { _, _ -> false },
                  num: (Int, Int) -> String? = { _, _ -> null }, letter: (Int, Int) -> String? = { _, _ -> null }) {
    val line = MaterialTheme.colorScheme.onSurface
    val paper = MaterialTheme.colorScheme.surface
    val dark = isSystemInDarkTheme()
    val tm = rememberTextMeasurer()
    BoxWithConstraints(Modifier.fillMaxWidth().padding(top = 8.dp), contentAlignment = Alignment.Center) {
        val cell = minOf(maxWidth / cols, 44.dp)
        Box(Modifier.size(cell * cols, cell * rows)
            .drawBehind {
                val c = size.width / cols
                drawRect(paper)
                for (r in 0 until rows) for (k in 0 until cols) {
                    val o = Offset(k * c, r * c)
                    if (black(k, r)) { drawRect(line, o, Size(c, c)); continue }
                    num(k, r)?.let { n ->
                        drawText(tm, n, o + Offset(c * 0.06f, c * 0.02f), TextStyle(color = line, fontSize = (c * 0.26f).toSp()))
                    }
                    letter(k, r)?.let { l ->
                        val t = tm.measure(l, TextStyle(color = line, fontSize = (c * 0.55f).toSp(), fontWeight = FontWeight.SemiBold))
                        drawText(t, topLeft = o + Offset((c - t.size.width) / 2, (c - t.size.height) / 2))
                    }
                }
                val thin = line.copy(alpha = 0.55f)
                for (k in 1 until cols) drawLine(if (thick > 0 && k % thick == 0) line else thin, Offset(k * c, 0f), Offset(k * c, size.height),
                    if (thick > 0 && k % thick == 0) 2.dp.toPx() else 0.7.dp.toPx())
                for (r in 1 until rows) drawLine(if (thick > 0 && r % thick == 0) line else thin, Offset(0f, r * c), Offset(size.width, r * c),
                    if (thick > 0 && r % thick == 0) 2.dp.toPx() else 0.7.dp.toPx())
                drawRect(line, style = Stroke(2.dp.toPx()))
            }
            .ink(ink, "board", relative = true, dark = dark, fingers = true))
    }
}
