// La Settimana di EdiKOla: the day's crossword (clues from the headlines), the crucipuzzle, three sudoku, two kakuro.
// Like on a paper magazine: the grid and the clues, nothing is checked, there are no solutions. Two ways to fill it
// in, chosen on the screen and kept for all games: Penna, you write on the grid with the pen or a finger and it stays
// a stroke (nothing is recognized); Tastiera, you tap a square and type. The stylus writes in both.
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
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.draw.alpha
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.gestures.detectTapGestures
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
    /** Penna (false) or Tastiera (true), for all games */
    var keyboard: Boolean
        get() = all().optBoolean("tastiera", false)
        set(v) { file.writeText(all().put("tastiera", v).toString()) }
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
    Triple("kakuro1", "Kakuro facile", "Somme: ogni riga e colonna bianca dà il numero indicato, senza cifre ripetute."),
    Triple("kakuro2", "Kakuro", "Schema più grande, somme più lunghe."),
)

@Composable
private fun toneOf(key: String): Tone {
    val pal = LocalPalette.current
    return when (key) { "cruciverba" -> pal.cruciverba; "crucipuzzle" -> pal.crucipuzzle; "kakuro1", "kakuro2" -> pal.giochi; else -> pal.sudoku }
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
        key.startsWith("kakuro") -> {
            val big = key == "kakuro2"
            val k = (0..5).firstNotNullOfOrNull { runCatching {
                Kakuro.generate(seed * 10 + it, if (big) 9 else 7, if (big) 9 else 7, if (big) 5 else 4) }.getOrNull() } ?: return null
            JSONObject().put("w", k.w).put("h", k.h)
                .put("white", (0 until k.w * k.h).joinToString("") { if (k.white[it]) "." else "#" })
                .put("down", JSONArray(k.down.toList())).put("across", JSONArray(k.across.toList()))
                .put("given", k.given.joinToString(""))
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
    var keys by remember { mutableStateOf(GiochiStore.keyboard && which != "crucipuzzle") }
    var typed by remember { mutableStateOf("") }   // what was typed, one character per square (' ' empty)
    var sel by remember { mutableIntStateOf(-1) }   // the square selected for the keyboard
    var across by remember { mutableStateOf(true) } // crossword: the direction of typing
    LaunchedEffect(renew) {
        InkDoc.rubber.value = false
        sel = -1
        val old = GiochiStore.get(which)
        // a saved one of older versions (no "id") is replaced by a new one
        st = (if (renew == 0 && old?.has("id") == true) old else null) ?: withContext(Dispatchers.Default) { make(which, renew > 0) }?.also {
            if (old?.has("id") == true) InkDoc.delete(GiochiStore.ink(which, old))
            GiochiStore.put(which, it)
        }
        typed = st?.optString("typed").orEmpty()
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
            // the layout of the game: size, black squares, what is printed in each square
            val g = remember(s) { Grid.of(which, s) }
            fun cell(i: Int) = typed.getOrNull(i)?.takeIf { it != ' ' }?.toString()
            fun save(t: String) { typed = t; GiochiStore.put(which, s.put("typed", t)) }
            fun type(i: Int, ch: Char) {
                val t = (typed.ifEmpty { " ".repeat(g.w * g.h) }).toCharArray()
                t[i] = ch
                save(String(t))
            }
            val word = if (which == "cruciverba" && sel >= 0) g.word(sel, across) else emptyList()
            Board(g, ink, keys, sel, word.toSet(), ::cell) { i ->
                if (!g.open(i)) return@Board
                if (i == sel && which == "cruciverba") across = !across
                sel = i
            }
            Tools(ink, keys.takeIf { which != "crucipuzzle" }, { keys = it; GiochiStore.keyboard = it; sel = -1 }) {
                ask = "cancella"
            }
            if (keys && sel >= 0) KeyInput(sel, digits = which != "cruciverba",
                onChar = { ch ->
                    type(sel, ch)
                    if (which == "cruciverba") word.getOrNull(word.indexOf(sel) + 1)?.let { sel = it }
                },
                onDelete = {
                    if (cell(sel) == null && which == "cruciverba") word.getOrNull(word.indexOf(sel) - 1)?.let { sel = it }
                    type(sel, ' ')
                })
            when {
                which == "cruciverba" -> {
                    val words = s.getJSONArray("words").objects()
                    // the clue being typed, then all of them
                    if (keys && word.isNotEmpty()) words.firstOrNull { w -> g.word(sel, across).firstOrNull() == w.getInt("y") * g.w + w.getInt("x") &&
                        w.getBoolean("a") == across }?.let { w ->
                        Text("${w.getInt("num")} ${if (across) "orizzontale" else "verticale"}: ${w.getString("clue")}",
                            Modifier.padding(bottom = 6.dp), fontFamily = Reading, fontWeight = FontWeight.SemiBold, color = tone.strong)
                    }
                    LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(bottom = 16.dp)) {
                        for (a in listOf(true, false)) {
                            item { Kicker(if (a) "Orizzontali" else "Verticali", tone.strong, Modifier.padding(top = 12.dp, bottom = 4.dp)) }
                            items(words.filter { it.getBoolean("a") == a }) { w ->
                                Row(Modifier.padding(vertical = 4.dp)) {
                                    Text("${w.getInt("num")}", Modifier.width(30.dp), fontWeight = FontWeight.Bold, color = tone.strong)
                                    Text("${w.getString("clue")} (${w.getString("word").length})", Modifier.weight(1f), fontFamily = Reading)
                                }
                            }
                        }
                    }
                }
                which == "crucipuzzle" -> LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(bottom = 16.dp)) {
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
                which.startsWith("kakuro") -> Text("Il numero sopra la diagonale è la somma della riga a destra, quello sotto " +
                    "la somma della colonna in basso. Le cifre vanno da 1 a 9 e in una somma non si ripetono.",
                    Modifier.padding(vertical = 8.dp), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
    ask?.let { what ->
        AlertDialog(onDismissRequest = { ask = null },
            title = { Text(if (what == "nuovo") "Nuovo schema?" else "Cancellare tutto?") },
            text = { Text(if (what == "nuovo") "Lo schema di adesso e quello che ci hai scritto si perdono." else "Tutto quello che hai scritto sullo schema.") },
            confirmButton = { TextButton(onClick = {
                ask = null
                if (what == "nuovo") renew++ else { ink?.clear(); st?.let { typed = ""; GiochiStore.put(which, it.put("typed", "")) } }
            }) { Text(if (what == "nuovo") "Nuovo" else "Cancella") } },
            dismissButton = { TextButton(onClick = { ask = null }) { Text("Annulla") } })
    }
}

/** What a game's grid looks like: w × h squares; black ones, their kakuro sums; what is printed in the others */
private class Grid(val w: Int, val h: Int, val black: BooleanArray, val printed: Array<String?>, val num: Array<String?>,
                   val down: IntArray? = null, val across: IntArray? = null, val thick: Int = 0) {
    /** a square you can write in */
    fun open(i: Int) = !black[i] && printed[i] == null

    /** the squares of the word through i in a direction (crossword) */
    fun word(i: Int, horizontal: Boolean): List<Int> {
        if (black[i]) return emptyList()
        val step = if (horizontal) 1 else w
        fun ok(j: Int) = j in 0 until w * h && !black[j] && (!horizontal || j / w == i / w)
        var a = i; while (ok(a - step)) a -= step
        val out = mutableListOf<Int>(); var b = a; while (ok(b)) { out += b; b += step }
        return out
    }

    companion object {
        fun of(key: String, s: JSONObject): Grid = when {
            key.startsWith("sudoku") -> {
                val puz = s.getString("puz")
                Grid(9, 9, BooleanArray(81), Array(81) { puz[it].takeIf { c -> c != '0' }?.toString() }, arrayOfNulls(81), thick = 3)
            }
            key == "cruciverba" -> {
                val rows = s.getJSONArray("rows").strings()
                val w = rows[0].length; val h = rows.size
                val num = arrayOfNulls<String>(w * h)
                s.getJSONArray("words").objects().forEach { num[it.getInt("y") * w + it.getInt("x")] = it.getInt("num").toString() }
                Grid(w, h, BooleanArray(w * h) { rows[it / w][it % w] == '.' }, arrayOfNulls(w * h), num)
            }
            key.startsWith("kakuro") -> {
                val w = s.getInt("w"); val h = s.getInt("h"); val white = s.getString("white"); val given = s.getString("given")
                val down = s.getJSONArray("down"); val across = s.getJSONArray("across")
                Grid(w, h, BooleanArray(w * h) { white[it] == '#' }, Array(w * h) { given[it].takeIf { c -> c != '0' }?.toString() },
                    arrayOfNulls(w * h), IntArray(w * h) { down.getInt(it) }, IntArray(w * h) { across.getInt(it) })
            }
            else -> {
                val rows = s.getJSONArray("rows").strings()
                val w = rows[0].length; val h = rows.size
                Grid(w, h, BooleanArray(w * h), Array(w * h) { rows[it / w][it % w].toString() }, arrayOfNulls(w * h))
            }
        }
    }
}

/** An invisible field that takes the keyboard's keys: each character, and delete */
@Composable
private fun KeyInput(at: Int, digits: Boolean, onChar: (Char) -> Unit, onDelete: () -> Unit) {
    val focus = remember { FocusRequester() }
    val kb = LocalSoftwareKeyboardController.current
    // a space always in the field, so that delete has something to delete
    var v by remember { mutableStateOf(TextFieldValue(" ", TextRange(1))) }
    LaunchedEffect(at) { focus.requestFocus(); kb?.show() } // every new square: the keyboard comes back if it was closed
    BasicTextField(v, { n ->
        when {
            n.text.isEmpty() -> onDelete()
            n.text.length > 1 -> n.text.drop(1).lastOrNull { if (digits) it in '1'..'9' else it.isLetter() }
                ?.let { onChar(Parole.norm(it.toString()).firstOrNull()?.uppercaseChar() ?: it.uppercaseChar()) }
        }
        v = TextFieldValue(" ", TextRange(1))
    }, Modifier.size(1.dp).alpha(0f).focusRequester(focus),
        keyboardOptions = KeyboardOptions(keyboardType = if (digits) KeyboardType.NumberPassword else KeyboardType.Password,
            autoCorrectEnabled = false))
}

/** Penna or Tastiera (null: only the pen), eraser for the pen, undo, clear */
@Composable
private fun Tools(ink: InkDoc, keys: Boolean?, setKeys: (Boolean) -> Unit, clear: () -> Unit) {
    var rubber by InkDoc.rubber
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        if (keys != null) {
            FilterChip(selected = !keys, onClick = { setKeys(false) }, label = { Text("Penna") })
            Spacer(Modifier.width(6.dp))
            FilterChip(selected = keys, onClick = { setKeys(true) }, label = { Text("Tastiera") })
            Spacer(Modifier.width(6.dp))
        }
        if (keys != true) FilterChip(selected = rubber, onClick = { rubber = !rubber }, label = { Text("Gomma") })
        Spacer(Modifier.weight(1f))
        if (keys != true) TextButton(onClick = { ink.undo() }) { Text("Annulla") }
        TextButton(onClick = clear) { Text("Cancella") }
    }
}

/** The grid, drawn like on paper: black squares (with the kakuro sums), numbers, printed letters or digits, what was
 *  typed; the ink on top. With the keyboard a tap selects a square; the stylus writes anyway. */
@Composable
private fun Board(g: Grid, ink: InkDoc, keys: Boolean, sel: Int, word: Set<Int>, typed: (Int) -> String?, tap: (Int) -> Unit) {
    val line = MaterialTheme.colorScheme.onSurface
    val paper = MaterialTheme.colorScheme.surface
    val mark = MaterialTheme.colorScheme.primaryContainer
    val written = LocalPalette.current.scritto
    val dark = isSystemInDarkTheme()
    val tm = rememberTextMeasurer()
    BoxWithConstraints(Modifier.fillMaxWidth().padding(top = 8.dp), contentAlignment = Alignment.Center) {
        val cell = minOf(maxWidth / g.w, 44.dp)
        Box(Modifier.size(cell * g.w, cell * g.h)
            .drawBehind {
                val c = size.width / g.w
                drawRect(paper)
                for (i in 0 until g.w * g.h) {
                    val o = Offset(i % g.w * c, i / g.w * c)
                    if (g.black[i]) {
                        drawRect(line, o, Size(c, c))
                        val d = g.down?.get(i) ?: 0; val a = g.across?.get(i) ?: 0
                        if (d > 0 || a > 0) {
                            drawLine(paper, o, o + Offset(c, c), 1.dp.toPx())
                            val st = TextStyle(color = paper, fontSize = (c * 0.28f).toSp(), fontWeight = FontWeight.Bold)
                            if (a > 0) { val t = tm.measure("$a", st); drawText(t, topLeft = o + Offset(c - t.size.width - c * 0.08f, c * 0.04f)) }
                            if (d > 0) { val t = tm.measure("$d", st); drawText(t, topLeft = o + Offset(c * 0.08f, c - t.size.height - c * 0.02f)) }
                        }
                        continue
                    }
                    if (i == sel) drawRect(mark, o, Size(c, c)) else if (i in word) drawRect(mark.copy(alpha = 0.45f), o, Size(c, c))
                    g.num[i]?.let { n -> drawText(tm, n, o + Offset(c * 0.06f, c * 0.02f), TextStyle(color = line, fontSize = (c * 0.26f).toSp())) }
                    val (l, col) = g.printed[i]?.let { it to line } ?: typed(i)?.let { it to written } ?: continue
                    val t = tm.measure(l, TextStyle(color = col, fontSize = (c * 0.55f).toSp(), fontWeight = FontWeight.SemiBold))
                    drawText(t, topLeft = o + Offset((c - t.size.width) / 2, (c - t.size.height) / 2))
                }
                val thin = line.copy(alpha = 0.55f)
                fun bold(k: Int) = g.thick > 0 && k % g.thick == 0
                for (k in 1 until g.w) drawLine(if (bold(k)) line else thin, Offset(k * c, 0f), Offset(k * c, size.height),
                    if (bold(k)) 2.dp.toPx() else 0.7.dp.toPx())
                for (r in 1 until g.h) drawLine(if (bold(r)) line else thin, Offset(0f, r * c), Offset(size.width, r * c),
                    if (bold(r)) 2.dp.toPx() else 0.7.dp.toPx())
                drawRect(line, style = Stroke(2.dp.toPx()))
            }
            .ink(ink, "board", relative = true, dark = dark, fingers = !keys)
            .pointerInput(keys, g) {
                if (keys) detectTapGestures { p ->
                    val c = size.width.toFloat() / g.w
                    tap((p.y / c).toInt().coerceIn(0, g.h - 1) * g.w + (p.x / c).toInt().coerceIn(0, g.w - 1))
                }
            })
    }
}
