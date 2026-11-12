// La Settimana di EdiKOla: the day's crossword (clues from the headlines), the crucipuzzle, three sudoku.
// Made on the phone, offline; every move is saved (files/giochi.json), so a puzzle waits where it was left.
package it.rimaturus.edikola

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
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
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** Saved puzzles, by key: "cruciverba", "crucipuzzle", "sudoku1".."sudoku3" */
object GiochiStore {
    private val file get() = File(Repo.app.filesDir, "giochi.json")
    val version = mutableIntStateOf(0)
    private fun all(): JSONObject = try { JSONObject(file.readText()) } catch (e: Exception) { JSONObject() }
    fun get(key: String): JSONObject? = all().optJSONObject(key)
    fun put(key: String, o: JSONObject) { file.writeText(all().put(key, o).toString()); version.intValue++ }
    fun seedOfToday(): Long = Store.today().replace("-", "").toLong()
}

private fun JSONArray.strings() = (0 until length()).map { getString(it) }
private fun JSONArray.ints() = (0 until length()).map { getInt(it) }.toMutableSet()

val LEVELS = listOf("facile", "medio", "difficile")

@Composable
fun GiochiCover() {
    val v by GiochiStore.version
    val pal = LocalPalette.current
    if (v < 0) return // read: the cover follows the saved puzzles
    fun status(key: String, words: (JSONObject) -> String): String {
        val o = GiochiStore.get(key) ?: return "Nuovo, da cominciare"
        return if (o.optBoolean("done")) "Risolto" else words(o)
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        GameCard("Cruciverba del giorno", "Schema libero: molte definizioni sono i titoli delle notizie di oggi, con la parola da trovare.",
            status("cruciverba") { o -> "In corso: ${o.getJSONArray("cur").strings().sumOf { r -> r.count { it == ' ' } }} caselle da riempire" },
            pal.cruciverba, Modifier.fillMaxWidth()) { Nav.go(Screen.Game("cruciverba")) }
        GameCard("Crucipuzzle", "Trova le parole nello schema: le lettere che restano, lette in ordine, formano la chiave.",
            status("crucipuzzle") { o -> "In corso: trovate ${o.getJSONObject("found").length()} di ${o.getJSONArray("words").length()}" },
            pal.crucipuzzle, Modifier.fillMaxWidth()) { Nav.go(Screen.Game("crucipuzzle")) }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            for (level in 1..3) {
                GameCard("Sudoku ${LEVELS[level - 1]}", null,
                    status("sudoku$level") { o -> "In corso: ${o.getString("cur").count { it == '0' }} vuote" },
                    pal.sudoku, Modifier.weight(1f)) { Nav.go(Screen.Game("sudoku$level")) }
            }
        }
    }
}

@Composable
private fun GameCard(title: String, text: String?, status: String, tone: Tone, modifier: Modifier, onClick: () -> Unit) {
    Card(modifier.clickable(onClick = onClick), colors = CardDefaults.cardColors(containerColor = tone.tint)) {
        Column(Modifier.padding(14.dp)) {
            Box(Modifier.width(46.dp).height(6.dp).background(tone.strong, RoundedCornerShape(3.dp)))
            Spacer(Modifier.height(8.dp))
            Text(title, color = tone.strong, fontFamily = FontFamily.Serif, fontWeight = FontWeight.Bold, fontSize = if (text != null) 22.sp else 17.sp)
            if (text != null) Text(text, style = MaterialTheme.typography.bodyMedium)
            Spacer(Modifier.height(6.dp))
            Text(status, color = tone.strong, fontWeight = FontWeight.Bold, style = MaterialTheme.typography.labelLarge)
        }
    }
}

/** How a square looks */
private class Look(val text: String = "", val bg: Color? = null, val fg: Color? = null, val num: String? = null, val block: Boolean = false)

/** A grid of squares; thick: every how many squares a thick line (sudoku: 3) */
@Composable
private fun Board(cols: Int, rows: Int, thick: Int = 0, look: (Int, Int) -> Look, onTap: (Int, Int) -> Unit) {
    val line = MaterialTheme.colorScheme.onSurface
    BoxWithConstraints(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        val cell: Dp = minOf(maxWidth / cols, 48.dp)
        Column(Modifier.border(1.5.dp, line).drawWithContent {
            drawContent()
            if (thick > 0) {
                val s = cell.toPx()
                for (k in thick until cols step thick) drawLine(line, Offset(k * s, 0f), Offset(k * s, rows * s), 2.5.dp.toPx())
                for (k in thick until rows step thick) drawLine(line, Offset(0f, k * s), Offset(cols * s, k * s), 2.5.dp.toPx())
            }
        }) {
            for (r in 0 until rows) Row {
                for (c in 0 until cols) {
                    val l = look(c, r)
                    Box(Modifier.size(cell).background(if (l.block) line else l.bg ?: MaterialTheme.colorScheme.surface)
                        .border(0.5.dp, line.copy(alpha = 0.5f)).clickable(enabled = !l.block) { onTap(c, r) },
                        contentAlignment = Alignment.Center) {
                        if (l.num != null) Text(l.num, Modifier.align(Alignment.TopStart).padding(start = 2.dp), fontSize = 8.sp,
                            color = l.fg ?: MaterialTheme.colorScheme.onSurface)
                        Text(l.text, fontSize = (cell.value * 0.55f).sp, fontWeight = FontWeight.Bold, color = l.fg ?: MaterialTheme.colorScheme.onSurface)
                    }
                }
            }
        }
    }
}

@Composable
private fun Keys(keys: List<Pair<String, () -> Unit>>, tone: Tone, height: Dp = 46.dp, size: Int = 18) {
    Row(Modifier.fillMaxWidth().padding(vertical = 2.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        for ((label, f) in keys) {
            Box(Modifier.weight(1f).height(height).background(tone.tint, RoundedCornerShape(8.dp)).clickable(onClick = f),
                contentAlignment = Alignment.Center) {
                Text(label, color = tone.strong, fontWeight = FontWeight.Bold, fontSize = size.sp, maxLines = 1)
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GameScreen(which: String) {
    val pal = LocalPalette.current
    var ask by remember { mutableStateOf(false) }
    var renew by remember { mutableIntStateOf(0) }
    val title = when {
        which == "cruciverba" -> "Cruciverba"
        which == "crucipuzzle" -> "Crucipuzzle"
        else -> "Sudoku " + LEVELS[which.last().digitToInt() - 1]
    }
    val tone = when (which) { "cruciverba" -> pal.cruciverba; "crucipuzzle" -> pal.crucipuzzle; else -> pal.sudoku }
    Scaffold(topBar = {
        TopAppBar(title = { Text(title, color = tone.strong, fontFamily = FontFamily.Serif, fontWeight = FontWeight.Bold) },
            navigationIcon = { IconButton(onClick = { Nav.back() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Indietro") } },
            actions = { TextButton(onClick = { ask = true }) { Text("Nuovo") } })
    }) { pad ->
        Box(Modifier.padding(pad).padding(horizontal = 10.dp)) {
            when (which) {
                "cruciverba" -> CruciverbaGame(tone, renew)
                "crucipuzzle" -> CrucipuzzleGame(tone, renew)
                else -> SudokuGame(which.last().digitToInt(), tone, renew)
            }
        }
    }
    if (ask) AlertDialog(onDismissRequest = { ask = false }, title = { Text("Nuovo gioco?") },
        text = { Text("Lo schema di adesso si perde.") },
        confirmButton = { TextButton(onClick = { ask = false; renew++ }) { Text("Nuovo") } },
        dismissButton = { TextButton(onClick = { ask = false }) { Text("Annulla") } })
}

@Composable
private fun Message(text: String?, close: () -> Unit) {
    if (text != null) AlertDialog(onDismissRequest = close, text = { Text(text) },
        confirmButton = { TextButton(onClick = close) { Text("OK") } })
}

// ---------------------------------------------------------------------------------------------- Sudoku

@Composable
private fun SudokuGame(level: Int, tone: Tone, renew: Int) {
    val key = "sudoku$level"
    val pal = LocalPalette.current
    var st by remember { mutableStateOf<JSONObject?>(null) }
    var sel by remember { mutableIntStateOf(-1) }
    var msg by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(renew) {
        st = (if (renew == 0) GiochiStore.get(key) else null) ?: withContext(Dispatchers.Default) {
            val seed = if (renew == 0) GiochiStore.seedOfToday() * 10 + level else System.currentTimeMillis() % 100000000
            val (puz, sol) = Sudoku.generate(seed, level)
            JSONObject().put("puz", puz).put("sol", sol).put("cur", puz).put("wrong", JSONArray())
        }.also { GiochiStore.put(key, it) }
        sel = -1
    }
    val s = st ?: return Text("Preparo lo schema…")
    val puz = s.getString("puz"); val sol = s.getString("sol"); val cur = s.getString("cur")
    val wrong = s.getJSONArray("wrong").ints()
    fun save(newCur: String, newWrong: Set<Int> = wrong) {
        val o = JSONObject(s.toString()).put("cur", newCur).put("wrong", JSONArray(newWrong.toList()))
        if (newCur == sol && !s.optBoolean("done")) { o.put("done", true); msg = "Sudoku risolto! Complimenti." }
        st = o; GiochiStore.put(key, o)
    }
    fun peer(i: Int, j: Int) = i / 9 == j / 9 || i % 9 == j % 9 || (i / 27 == j / 27 && (i % 9) / 3 == (j % 9) / 3)
    fun put(v: Char) {
        if (sel < 0 || puz[sel] != '0' || s.optBoolean("done")) return
        save(cur.substring(0, sel) + v + cur.substring(sel + 1), wrong - sel)
    }
    Column(Modifier.verticalScroll(rememberScrollState())) {
        Spacer(Modifier.height(8.dp))
        Board(9, 9, thick = 3, look = { c, r ->
            val i = r * 9 + c
            val v = cur[i]
            val given = puz[i] != '0'
            when {
                i == sel -> Look(if (v != '0') v.toString() else "", tone.strong, tone.onStrong)
                else -> Look(if (v != '0') v.toString() else "",
                    if (sel >= 0 && (peer(i, sel) || (v != '0' && v == cur[sel]))) tone.tint else null,
                    if (given) null else if (i in wrong) pal.errore else pal.scritto)
            }
        }, onTap = { c, r -> sel = r * 9 + c })
        Text(if (s.optBoolean("done")) "Risolto!" else "Caselle vuote: ${cur.count { it == '0' }} - tocca una casella, poi un numero",
            Modifier.fillMaxWidth().padding(vertical = 8.dp), textAlign = TextAlign.Center, color = tone.strong)
        Keys((1..9).map { n -> n.toString() to { put('0' + n) } }, tone, 52.dp, 22)
        Keys(listOf(
            "Cancella" to { put('0') },
            "Controlla" to {
                val bad = (0 until 81).filter { cur[it] != '0' && cur[it] != sol[it] }.toSet()
                save(cur, bad)
                msg = if (bad.isEmpty()) "Fin qui è tutto giusto." else "Numeri sbagliati: ${bad.size}, ora sono in rosso."
            },
            "Aiuto" to { if (sel >= 0 && puz[sel] == '0') { val c = sol[sel]; save(cur.substring(0, sel) + c + cur.substring(sel + 1), wrong - sel) } },
        ), tone, 46.dp, 16)
    }
    Message(msg) { msg = null }
}

// ---------------------------------------------------------------------------------------------- Cruciverba

private fun todaysHeadlines() = Repo.todays().flatMap { (p, ed) -> ed.articles.map { Parole.Headline(it.title, p.name) } }
    .filter { Testo.lang(it.title) == "it" }

@Composable
private fun CruciverbaGame(tone: Tone, renew: Int) {
    val pal = LocalPalette.current
    var st by remember { mutableStateOf<JSONObject?>(null) }
    var sx by remember { mutableIntStateOf(-1) }
    var sy by remember { mutableIntStateOf(-1) }
    var across by remember { mutableStateOf(true) }
    var msg by remember { mutableStateOf<String?>(null) }
    var showClues by remember { mutableStateOf(false) }
    LaunchedEffect(renew) {
        st = (if (renew == 0) GiochiStore.get("cruciverba") else null) ?: withContext(Dispatchers.Default) {
            val seed = if (renew == 0) GiochiStore.seedOfToday() else System.currentTimeMillis() % 100000000
            val cw = Cruciverba.generate(Parole.fromNews(todaysHeadlines(), 11), Parole.dictionary, seed)
            JSONObject().put("rows", JSONArray(cw.rows)).put("cur", JSONArray(cw.rows.map { r -> r.map { if (it == '.') '.' else ' ' }.joinToString("") }))
                .put("words", JSONArray().apply {
                    cw.words.forEach { w -> put(JSONObject().put("word", w.word).put("clue", w.clue).put("source", w.source ?: "")
                        .put("x", w.x).put("y", w.y).put("a", w.across).put("num", w.num)) }
                }).put("wrong", JSONArray())
        }.also { GiochiStore.put("cruciverba", it) }
        sx = -1
    }
    val s = st ?: return Text("Preparo lo schema con le notizie di oggi…")
    val rows = s.getJSONArray("rows").strings()
    val cur = s.getJSONArray("cur").strings()
    val wrong = s.getJSONArray("wrong").ints()
    val words = s.getJSONArray("words").let { a -> (0 until a.length()).map { a.getJSONObject(it) } }
    val h = rows.size; val w = rows[0].length
    fun isLetter(x: Int, y: Int) = y in 0 until h && x in 0 until w && rows[y][x] != '.'
    fun wordAt(x: Int, y: Int, a: Boolean): Pair<JSONObject, Int>? {
        for (wd in words) {
            if (wd.getBoolean("a") != a) continue
            val k = if (a) x - wd.getInt("x") else y - wd.getInt("y")
            val len = wd.getString("word").length
            if (k in 0 until len && wd.getInt("x") + (if (a) k else 0) == x && wd.getInt("y") + (if (a) 0 else k) == y) return wd to k
        }
        return null
    }
    if (sx < 0) { val f = words.first(); sx = f.getInt("x"); sy = f.getInt("y"); across = f.getBoolean("a") }
    val (wd, k) = wordAt(sx, sy, across) ?: wordAt(sx, sy, !across)?.also { across = !across } ?: (words.first() to 0)
    val inWord = mutableSetOf<Int>()
    run {
        val a = wd.getBoolean("a")
        for (i in 0 until wd.getString("word").length) inWord += (wd.getInt("y") + if (a) 0 else i) * 100 + wd.getInt("x") + if (a) i else 0
    }
    val nums = words.associate { (it.getInt("y") * 100 + it.getInt("x")) to it.getInt("num").toString() }
    fun save(newCur: List<String>, newWrong: Set<Int>) {
        val o = JSONObject(s.toString()).put("cur", JSONArray(newCur)).put("wrong", JSONArray(newWrong.toList()))
        if (newCur == rows && !s.optBoolean("done")) { o.put("done", true); msg = "Cruciverba completato!\n\nComplimenti." }
        st = o; GiochiStore.put("cruciverba", o)
    }
    fun set(x: Int, y: Int, ch: Char): List<String> = cur.toMutableList().also { it[y] = it[y].substring(0, x) + ch + it[y].substring(x + 1) }
    fun type(ch: Char) {
        if (s.optBoolean("done")) return
        save(set(sx, sy, ch), wrong - (sy * 100 + sx))
        if (k < wd.getString("word").length - 1) { if (wd.getBoolean("a")) sx++ else sy++ }
    }
    fun back() {
        if (s.optBoolean("done")) return
        if (cur[sy][sx] == ' ' && k > 0) { if (wd.getBoolean("a")) sx-- else sy-- }
        save(set(sx, sy, ' '), wrong - (sy * 100 + sx))
    }
    Column {
        val src = wd.optString("source")
        Column(Modifier.fillMaxWidth().padding(vertical = 6.dp).background(tone.tint, RoundedCornerShape(10.dp)).padding(10.dp)) {
            Text("${wd.getInt("num")} ${if (wd.getBoolean("a")) "orizzontale" else "verticale"} - ${wd.getString("word").length} lettere",
                color = tone.strong, fontWeight = FontWeight.Bold, style = MaterialTheme.typography.labelLarge)
            Text(wd.getString("clue") + if (src.isNotEmpty()) "  (dal titolo di $src)" else "", maxLines = 3, overflow = TextOverflow.Ellipsis,
                fontFamily = FontFamily.Serif)
        }
        Board(w, h, look = { c, r ->
            if (!isLetter(c, r)) Look(block = true)
            else if (c == sx && r == sy) Look(cur[r][c].toString().trim(), tone.strong, tone.onStrong, nums[r * 100 + c])
            else Look(cur[r][c].toString().trim(), if (r * 100 + c in inWord) tone.tint else null,
                if (r * 100 + c in wrong) pal.errore else pal.scritto, nums[r * 100 + c])
        }, onTap = { c, r ->
            if (c == sx && r == sy) { if (wordAt(c, r, !across) != null) { across = !across } } else { sx = c; sy = r }
        })
        if (s.optBoolean("done")) Text("Risolto! Complimenti.", Modifier.fillMaxWidth().padding(4.dp), color = tone.strong,
            textAlign = TextAlign.Center, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(6.dp))
        Keys("QWERTYUIOP".map { ch -> ch.toString() to { type(ch) } }, tone)
        Keys("ASDFGHJKL".map { ch -> ch.toString() to { type(ch) } }, tone)
        Keys("ZXCVBNM".map { ch -> ch.toString() to { type(ch) } } + ("⌫" to { back() }), tone)
        Keys(listOf(
            "Definizioni" to { showClues = true },
            "Verso" to { if (wordAt(sx, sy, !across) != null) { across = !across } },
            "Controlla" to {
                val bad = mutableSetOf<Int>()
                for (y in 0 until h) for (x in 0 until w) if (cur[y][x] != ' ' && cur[y][x] != '.' && cur[y][x] != rows[y][x]) bad += y * 100 + x
                save(cur, bad)
                msg = if (bad.isEmpty()) "Fin qui è tutto giusto." else "Lettere sbagliate: ${bad.size}, ora sono in rosso."
            },
            "Aiuto" to { if (!s.optBoolean("done")) save(set(sx, sy, rows[sy][sx]), wrong - (sy * 100 + sx)) },
        ), tone, 42.dp, 14)
    }
    Message(msg) { msg = null }
    if (showClues) AlertDialog(onDismissRequest = { showClues = false }, title = { Text("Definizioni") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                var last: Boolean? = null
                for (x in words) {
                    val a = x.getBoolean("a")
                    if (a != last) { last = a; Text(if (a) "ORIZZONTALI" else "VERTICALI", color = tone.strong, fontWeight = FontWeight.Bold,
                        modifier = Modifier.padding(top = 8.dp)) }
                    Text("${x.getInt("num")}. ${x.getString("clue")} (${x.getString("word").length})",
                        Modifier.fillMaxWidth().clickable { sx = x.getInt("x"); sy = x.getInt("y"); across = a; showClues = false }.padding(vertical = 6.dp),
                        fontFamily = FontFamily.Serif)
                }
            }
        },
        confirmButton = { TextButton(onClick = { showClues = false }) { Text("Chiudi") } })
}

// ---------------------------------------------------------------------------------------------- Crucipuzzle

@Composable
private fun CrucipuzzleGame(tone: Tone, renew: Int) {
    val pal = LocalPalette.current
    var st by remember { mutableStateOf<JSONObject?>(null) }
    var start by remember { mutableStateOf<Pair<Int, Int>?>(null) }
    var msg by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(renew) {
        st = (if (renew == 0) GiochiStore.get("crucipuzzle") else null) ?: withContext(Dispatchers.Default) {
            val seed = if (renew == 0) GiochiStore.seedOfToday() else System.currentTimeMillis() % 100000000
            val pool = Parole.fromNews(todaysHeadlines(), 10) + Parole.dictionary
            var wp: Crucipuzzle.Puzzle? = null
            for (t in 0..5) { wp = Crucipuzzle.generate(pool, seed + t); if (wp != null) break }
            val p = wp ?: return@withContext null
            JSONObject().put("rows", JSONArray(p.rows)).put("key", p.key).put("found", JSONObject())
                .put("words", JSONArray().apply { p.words.forEach { put(JSONObject().put("word", it.word).put("x", it.x).put("y", it.y).put("dx", it.dx).put("dy", it.dy)) } })
        }?.also { GiochiStore.put("crucipuzzle", it) }
        start = null
    }
    val s = st ?: return Text("Preparo lo schema…")
    val rows = s.getJSONArray("rows").strings()
    val words = s.getJSONArray("words").let { a -> (0 until a.length()).map { a.getJSONObject(it) } }
    val found = s.getJSONObject("found")
    val all = found.length() == words.size
    val cover = mutableMapOf<Int, Int>()
    val inAny = mutableSetOf<Int>()
    for (p in words) {
        val f = if (found.has(p.getString("word"))) found.getInt(p.getString("word")) else null
        for (k in 0 until p.getString("word").length) {
            val i = (p.getInt("y") + p.getInt("dy") * k) * 100 + p.getInt("x") + p.getInt("dx") * k
            inAny += i
            if (f != null) cover[i] = f
        }
    }
    fun mark(word: String) {
        val o = JSONObject(s.toString())
        val f = o.getJSONObject("found")
        f.put(word, f.length() % 8)
        st = o; GiochiStore.put("crucipuzzle", o)
        if (f.length() == words.size) msg = "Tutte le parole trovate!\n\nLe lettere rimaste formano la chiave:\n" + s.getString("key")
    }
    fun tap(c: Int, r: Int) {
        val st0 = start
        if (st0 == null) { start = c to r; return }
        start = null
        if (st0 == (c to r)) return
        var dx = c - st0.first; var dy = r - st0.second
        val n = maxOf(Math.abs(dx), Math.abs(dy))
        if (dx == 0 || dy == 0 || Math.abs(dx) == Math.abs(dy)) {
            dx /= n; dy /= n
            val word = (0..n).map { rows[st0.second + dy * it][st0.first + dx * it] }.joinToString("")
            val hit = words.map { it.getString("word") }.firstOrNull { !found.has(it) && (it == word || it == word.reversed()) }
            if (hit != null) return mark(hit)
        }
        msg = "Non è una delle parole dell'elenco."
    }
    Column(Modifier.verticalScroll(rememberScrollState())) {
        Spacer(Modifier.height(8.dp))
        Board(rows[0].length, rows.size, look = { c, r ->
            val i = r * 100 + c
            when {
                start == (c to r) -> Look(rows[r][c].toString(), tone.strong, tone.onStrong)
                cover[i] != null -> Look(rows[r][c].toString(), pal.found[cover.getValue(i)])
                all && i !in inAny -> Look(rows[r][c].toString(), pal.giochi.strong, pal.giochi.onStrong)
                else -> Look(rows[r][c].toString())
            }
        }, onTap = { c, r -> tap(c, r) })
        Text(if (all) "La chiave: " + s.getString("key") else "Trovate ${found.length()} di ${words.size} - tocca la prima e l'ultima lettera di una parola",
            Modifier.fillMaxWidth().padding(vertical = 8.dp), textAlign = TextAlign.Center, color = tone.strong,
            fontWeight = if (all) FontWeight.Bold else FontWeight.Normal)
        for (row in words.chunked(3)) Row(horizontalArrangement = Arrangement.spacedBy(4.dp), modifier = Modifier.padding(vertical = 2.dp)) {
            for (p in row) {
                val wd = p.getString("word")
                val f = if (found.has(wd)) found.getInt(wd) else null
                Text(wd, Modifier.weight(1f).background(f?.let { pal.found[it] } ?: Color.Transparent, RoundedCornerShape(6.dp)).padding(4.dp),
                    textAlign = TextAlign.Center, fontWeight = if (f == null) FontWeight.Bold else FontWeight.Normal, fontSize = 14.sp)
            }
            repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
        }
        Spacer(Modifier.height(6.dp))
        Keys(listOf("Soluzione" to {
            val o = JSONObject(s.toString())
            val f = o.getJSONObject("found")
            words.forEach { if (!f.has(it.getString("word"))) f.put(it.getString("word"), f.length() % 8) }
            st = o; GiochiStore.put("crucipuzzle", o)
        }), tone, 44.dp, 16)
    }
    Message(msg) { msg = null }
}
