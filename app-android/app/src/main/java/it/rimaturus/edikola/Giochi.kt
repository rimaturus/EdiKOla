// Puzzle generators, ported from the KOReader plugin (knp_parole, knp_sudoku, knp_crucipuzzle, knp_cruciverba).
// Pure Kotlin: no Android, so they compile and run on any JVM.
package it.rimaturus.edikola

import java.text.Normalizer

/** Park-Miller "minimal standard" generator: the same sequence for the same seed. next(n) is 1..n. */
class Rng(seed: Long) {
    private var s = Math.floorMod(Math.abs(seed), 2147483646L) + 1
    fun next(n: Int): Int {
        s = s * 16807 % 2147483647
        return (s % n).toInt() + 1
    }
}

fun <T> MutableList<T>.shuffleWith(rng: Rng): MutableList<T> {
    for (i in size - 1 downTo 1) {
        val j = rng.next(i + 1) - 1
        val t = this[i]; this[i] = this[j]; this[j] = t
    }
    return this
}

object Parole {
    /** "PERCHE": upper case A-Z, accents dropped (crossword spelling) */
    fun norm(s: String): String =
        Normalizer.normalize(s, Normalizer.Form.NFD).uppercase().filter { it in 'A'..'Z' }

    data class Entry(val word: String, val clue: String, val source: String? = null)

    val dictionary: List<Entry> = ParoleData.DICT.map { Entry(it.first, it.second) }
    val keys: List<String> = ParoleData.KEYS

    data class Headline(val title: String, val paper: String)

    /** Puzzle words out of today's headlines; the clue is the headline with the word blanked out.
     *  One word per headline (its longest usable one, only plain or accented Latin letters), no repeats. */
    fun fromNews(articles: List<Headline>, maxLen: Int = 11): List<Entry> {
        val out = mutableListOf<Entry>()
        val seen = mutableSetOf<String>()
        for (a in articles) {
            var best: String? = null
            var bestTok: String? = null
            val clean = a.title.replace('‘', ' ').replace('’', ' ')
            for (tok in clean.split(Regex("[\\s\\p{Punct}]+"))) {
                if (tok.isEmpty() || !tok.all { it.isLetter() && (it in 'A'..'Z' || it in 'a'..'z' || it in 'À'..'ÿ') }) continue
                val w = norm(tok)
                if (w.length in 4..maxLen && w.length == tok.length && w !in ParoleData.STOP && w !in seen &&
                    (best == null || w.length > best.length)) {
                    best = w; bestTok = tok
                }
            }
            if (best != null && bestTok != null) {
                seen += best
                val i = a.title.indexOf(bestTok)
                val clue = if (i >= 0) a.title.substring(0, i) + "..." + a.title.substring(i + bestTok.length) else a.title
                out += Entry(best, clue, a.paper)
            }
        }
        return out
    }
}

object Sudoku {
    val CLUES = intArrayOf(38, 30, 25) // facile, medio, difficile: how many digits are given (at least)

    private fun candidates(g: IntArray, i: Int): List<Int> {
        val r = i / 9; val c = i % 9
        val used = BooleanArray(10)
        for (k in 0 until 9) { used[g[r * 9 + k]] = true; used[g[k * 9 + c]] = true }
        val br = r - r % 3; val bc = c - c % 3
        for (dr in 0..2) for (dc in 0..2) used[g[(br + dr) * 9 + bc + dc]] = true
        return (1..9).filter { !used[it] }
    }

    /** the empty cell with the fewest candidates, or -1 when the grid is full */
    private fun tightest(g: IntArray): Pair<Int, List<Int>> {
        var best = -1
        var bestC: List<Int> = emptyList()
        for (i in 0 until 81) {
            if (g[i] == 0) {
                val c = candidates(g, i)
                if (c.isEmpty()) return i to c
                if (best < 0 || c.size < bestC.size) { best = i; bestC = c }
            }
        }
        return best to bestC
    }

    private fun fill(g: IntArray, rng: Rng): Boolean {
        val (i, c) = tightest(g)
        if (i < 0) return true
        for (v in c.toMutableList().shuffleWith(rng)) {
            g[i] = v
            if (fill(g, rng)) return true
        }
        g[i] = 0
        return false
    }

    /** Number of solutions of g, counting no further than limit. g is left as it was. */
    fun solutions(g: IntArray, limit: Int): Int {
        val (i, c) = tightest(g)
        if (i < 0) return 1
        var n = 0
        for (v in c) {
            g[i] = v
            n += solutions(g, limit - n)
            if (n >= limit) break
        }
        g[i] = 0
        return n
    }

    /** puzzle and solution, 81 digits each (0 = empty); level 1..3. Exactly one solution, symmetric clues. */
    fun generate(seed: Long, level: Int): Pair<String, String> {
        val rng = Rng(seed)
        val sol = IntArray(81)
        fill(sol, rng)
        val puz = sol.copyOf()
        val order = (0..40).toMutableList().shuffleWith(rng) // cell i and its mirror 80 - i (40 is the centre)
        var clues = 81
        val target = CLUES.getOrElse(level - 1) { CLUES[1] }
        for (i in order) {
            val j = 80 - i
            val n = if (i == j) 1 else 2
            if (clues - n >= target) {
                val a = puz[i]; val b = puz[j]
                puz[i] = 0; puz[j] = 0
                if (solutions(puz, 2) == 1) clues -= n else { puz[i] = a; puz[j] = b }
            }
        }
        return puz.joinToString("") to sol.joinToString("")
    }
}

/** Word search with a key: words in 8 directions, the leftover letters spell a proverb or a wish. */
object Crucipuzzle {
    data class Placed(val word: String, val x: Int, val y: Int, val dx: Int, val dy: Int)
    data class Puzzle(val w: Int, val h: Int, val rows: List<String>, val words: List<Placed>, val key: String)

    private val DIRS = listOf(1 to 0, 0 to 1, 1 to 1, 1 to -1, -1 to 0, 0 to -1, -1 to -1, -1 to 1)

    /** How many times word can be read in the grid, in all 8 directions (a palindrome counts once). */
    fun count(rows: List<String>, word: String): Int {
        val h = rows.size; val w = rows[0].length
        var n = 0
        for (y in 0 until h) for (x in 0 until w) {
            if (rows[y][x] != word[0]) continue
            for ((dx, dy) in DIRS) {
                var k = 1
                while (k < word.length) {
                    val cx = x + dx * k; val cy = y + dy * k
                    if (cy !in 0 until h || cx !in 0 until w || rows[cy][cx] != word[k]) break
                    k++
                }
                if (k == word.length) n++
            }
        }
        if (word.length > 1 && word == word.reversed()) n /= 2
        return n
    }

    private class Saved(val g: Array<Char?>, val placed: List<Placed>, val key: String)

    private fun attempt(pool: List<String>, w: Int, h: Int, rng: Rng, byLen: Map<Int, List<String>>): Saved? {
        val g = arrayOfNulls<Char>(w * h)
        val placed = mutableListOf<Placed>()
        var empties = w * h
        var saved: Saved? = null
        fun tryWord(word: String): Triple<Int, Int, Pair<Int, Int>>? {
            var best: Triple<Int, Int, Pair<Int, Int>>? = null
            var bestOv = -1
            repeat(120) {
                val d = DIRS[rng.next(8) - 1]
                val x = rng.next(w) - 1; val y = rng.next(h) - 1
                val ex = x + d.first * (word.length - 1); val ey = y + d.second * (word.length - 1)
                if (ex in 0 until w && ey in 0 until h) {
                    var ov = 0; var ok = true
                    for (k in word.indices) {
                        val c = g[(y + d.second * k) * w + x + d.first * k]
                        if (c != null) { if (c != word[k]) { ok = false; break }; ov++ }
                    }
                    if (ok && ov < word.length && ov > bestOv) { best = Triple(x, y, d); bestOv = ov }
                }
            }
            return best
        }
        for (word in pool) {
            if (empties < 6) break
            val s = tryWord(word) ?: continue
            for (k in word.indices) {
                val i = (s.second + s.third.second * k) * w + s.first + s.third.first * k
                if (g[i] == null) empties--
                g[i] = word[k]
            }
            placed += Placed(word, s.first, s.second, s.third.first, s.third.second)
            val keys = byLen[empties]
            if (keys != null && placed.size >= 8) saved = Saved(g.copyOf(), placed.toList(), keys[rng.next(keys.size) - 1])
        }
        return saved
    }

    private fun finish(s: Saved, w: Int, h: Int): Puzzle? {
        val key = Parole.norm(s.key)
        var k = 0
        val rows = (0 until h).map { y ->
            buildString { for (x in 0 until w) append(s.g[y * w + x] ?: key[k++]) }
        }
        if (s.placed.any { count(rows, it.word) != 1 }) return null
        return Puzzle(w, h, rows, s.placed.sortedBy { it.word }, s.key)
    }

    fun generate(entries: List<Parole.Entry>, seed: Long, w: Int = 10, h: Int = 10, tries: Int = 60): Puzzle? {
        val byLen = Parole.keys.groupBy { Parole.norm(it).length }
        val words = entries.map { it.word }.filter { it.length >= 4 && it.length <= maxOf(w, h) }.distinct()
        var best: Puzzle? = null
        for (t in 1..tries) {
            val rng = Rng(seed * 131 + t)
            val pool = mutableListOf<String>()
            for (wd in words.toMutableList().shuffleWith(rng)) {
                val inside = pool.any { o -> o.contains(wd) || wd.contains(o) || o.contains(wd.reversed()) || wd.contains(o.reversed()) }
                if (!inside) pool += wd
                if (pool.size >= 26) break
            }
            pool.sortByDescending { it.length } // long words first, short ones fill the gaps
            val done = attempt(pool, w, h, rng, byLen)?.let { finish(it, w, h) }
            if (done != null && (best == null || done.words.size > best.words.size)) best = done
            if (best != null && best.words.size >= 16) break
        }
        return best
    }
}

/** "Schema libero" crossword: headline words first, then the dictionary. */
object Cruciverba {
    data class Word(val word: String, val clue: String, val source: String?, val x: Int, val y: Int, val across: Boolean, var num: Int = 0)
    data class Puzzle(val w: Int, val h: Int, val rows: List<String>, val words: List<Word>) // '.' = black square

    private class Attempt(val grid: Array<Array<Char?>>, val placed: MutableList<Word>, val crossings: Int, val w: Int, val h: Int)

    private fun attempt(news: List<Parole.Entry>, dict: List<Parole.Entry>, w: Int, h: Int, want: Int, rng: Rng): Attempt {
        val grid = Array(h) { arrayOfNulls<Char>(w) }
        val usedA = Array(h) { BooleanArray(w) }
        val usedD = Array(h) { BooleanArray(w) }
        fun at(x: Int, y: Int): Char? = if (y in 0 until h && x in 0 until w) grid[y][x] else null
        val placed = mutableListOf<Word>()
        val seen = mutableSetOf<String>()
        val byLetter = mutableMapOf<Char, MutableList<Pair<Int, Int>>>()

        fun fit(word: String, x: Int, y: Int, across: Boolean): Int? {
            val dx = if (across) 1 else 0; val dy = if (across) 0 else 1
            val n = word.length
            if (x < 0 || y < 0 || x + dx * (n - 1) >= w || y + dy * (n - 1) >= h) return null
            if (at(x - dx, y - dy) != null || at(x + dx * n, y + dy * n) != null) return null
            var crossings = 0
            for (k in 0 until n) {
                val cx = x + dx * k; val cy = y + dy * k
                val l = at(cx, cy)
                if (l != null) {
                    if (l != word[k] || (if (across) usedA[cy][cx] else usedD[cy][cx])) return null
                    crossings++
                } else if (at(cx + dy, cy + dx) != null || at(cx - dy, cy - dx) != null) return null
            }
            return crossings
        }

        fun put(e: Parole.Entry, x: Int, y: Int, across: Boolean) {
            val dx = if (across) 1 else 0; val dy = if (across) 0 else 1
            for (k in e.word.indices) {
                val cx = x + dx * k; val cy = y + dy * k
                if (grid[cy][cx] == null) {
                    grid[cy][cx] = e.word[k]
                    byLetter.getOrPut(e.word[k]) { mutableListOf() } += cx to cy
                }
                if (across) usedA[cy][cx] = true else usedD[cy][cx] = true
            }
            seen += e.word
            placed += Word(e.word, e.clue, e.source, x, y, across)
        }

        fun spot(e: Parole.Entry): Triple<Int, Int, Boolean>? {
            var best: Triple<Int, Int, Boolean>? = null
            var bestScore = -1
            for (k in e.word.indices) for (p in byLetter[e.word[k]] ?: emptyList<Pair<Int, Int>>()) for (across in listOf(true, false)) {
                val x = p.first - if (across) k else 0
                val y = p.second - if (across) 0 else k
                val cr = fit(e.word, x, y, across)
                if (cr != null && cr > 0) {
                    val score = cr * 100 + rng.next(99)
                    if (score > bestScore) { best = Triple(x, y, across); bestScore = score }
                }
            }
            return best
        }

        val order = news.toMutableList().shuffleWith(rng).sortedByDescending { it.word.length }.toMutableList()
        order += dict.toMutableList().shuffleWith(rng)
        order.firstOrNull { it.word.length <= w }?.let { put(it, (w - it.word.length) / 2, h / 2, true) }
        var crossings = 0
        repeat(3) { // later words open new crossings for the ones skipped before
            for (e in order) {
                if (placed.size >= want) break
                if (e.word !in seen && e.word.length >= 3) {
                    val s = spot(e) ?: continue
                    crossings += fit(e.word, s.first, s.second, s.third) ?: 0
                    put(e, s.first, s.second, s.third)
                }
            }
        }
        return Attempt(grid, placed, crossings, w, h)
    }

    private fun finish(a: Attempt): Puzzle {
        var x0 = a.w; var y0 = a.h; var x1 = 0; var y1 = 0
        for (y in 0 until a.h) for (x in 0 until a.w) if (a.grid[y][x] != null) {
            x0 = minOf(x0, x); y0 = minOf(y0, y); x1 = maxOf(x1, x); y1 = maxOf(y1, y)
        }
        val rows = (y0..y1).map { y -> (x0..x1).map { x -> a.grid[y][x] ?: '.' }.joinToString("") }
        val words = a.placed.map { it.copy(x = it.x - x0, y = it.y - y0) }
        val starts = words.map { it.y * 1000 + it.x }.toSet()
        val nums = mutableMapOf<Int, Int>()
        var num = 0
        for (y in rows.indices) for (x in rows[0].indices) if (y * 1000 + x in starts) nums[y * 1000 + x] = ++num
        words.forEach { it.num = nums.getValue(it.y * 1000 + it.x) }
        return Puzzle(x1 - x0 + 1, y1 - y0 + 1, rows, words.sortedWith(compareBy({ !it.across }, { it.num })))
    }

    fun generate(news: List<Parole.Entry>, dict: List<Parole.Entry>, seed: Long, w: Int = 12, h: Int = 11, want: Int = 18, tries: Int = 30): Puzzle {
        var best: Attempt? = null
        var bestScore = -1
        for (t in 1..tries) {
            val a = attempt(news, dict, w, h, want, Rng(seed * 97 + t))
            val score = a.placed.size * 1000 + a.crossings
            if (score > bestScore) { best = a; bestScore = score }
            if (a.placed.size >= want) break
        }
        return finish(best!!)
    }
}

/** Kakuro: fill the white cells with 1..9 so that every run (across or down, between black cells) has no repeated
 *  digit and adds up to the number in the black cell before it. The grid is symmetric and has exactly one solution:
 *  when the sums alone allow more than one, a few digits are given, as in the magazines. */
object Kakuro {
    /** w × h cells, row by row; down[i], across[i]: the sums written in black cell i (0: none) */
    class Puzzle(val w: Int, val h: Int, val white: BooleanArray, val down: IntArray, val across: IntArray, val given: IntArray)

    private class Run(val cells: IntArray, var sum: Int = 0)

    /** The runs of a pattern: across ones first, then down ones; each white cell is in one of each */
    private fun runs(w: Int, h: Int, white: BooleanArray): List<Run> {
        val out = mutableListOf<Run>()
        for (r in 0 until h) { var c = 0
            while (c < w) { if (!white[r * w + c]) { c++; continue }
                val s = c; while (c < w && white[r * w + c]) c++
                out += Run(IntArray(c - s) { r * w + s + it }) } }
        for (c in 0 until w) { var r = 0
            while (r < h) { if (!white[r * w + c]) { r++; continue }
                val s = r; while (r < h && white[r * w + c]) r++
                out += Run(IntArray(r - s) { (s + it) * w + c }) } }
        return out
    }

    /** A pattern: black first row and column, black squares mirrored around the centre, runs of 2..maxRun cells,
     *  all white cells connected. Null when this attempt doesn't make one. */
    private fun pattern(w: Int, h: Int, rng: Rng, maxRun: Int): BooleanArray? {
        val white = BooleanArray(w * h) { it / w > 0 && it % w > 0 }
        // mirror of (r, c) inside the white area 1..h-1 × 1..w-1 is (h - r, w - c)
        fun blackSym(i: Int) { val r = i / w; val c = i % w; white[i] = false; white[(h - r) * w + (w - c)] = false }
        repeat((w - 1) * (h - 1) / 5) { val i = (rng.next(h - 1)) * w + rng.next(w - 1); blackSym(i) }
        var changed = true
        while (changed) {
            changed = false
            for (run in runs(w, h, white)) {
                if (run.cells.size == 1) { blackSym(run.cells[0]); changed = true }
                else if (run.cells.size > maxRun) { blackSym(run.cells[1 + rng.next(run.cells.size - 2) - 1]); changed = true }
                if (changed) break
            }
        }
        val whites = (0 until w * h).filter { white[it] }
        if (whites.size < (w - 1) * (h - 1) / 2) return null
        val seen = BooleanArray(w * h); val todo = ArrayDeque(listOf(whites[0])); seen[whites[0]] = true; var n = 0
        while (todo.isNotEmpty()) { val i = todo.removeFirst(); n++
            for (j in intArrayOf(i - 1, i + 1, i - w, i + w)) if (j in 0 until w * h && white[j] && !seen[j] &&
                (j / w == i / w || j % w == i % w)) { seen[j] = true; todo.add(j) } }
        return if (n == whites.size) white else null
    }

    /** Number of fillings of the runs with their sums, counting no further than limit */
    private fun count(w: Int, h: Int, runs: List<Run>, limit: Int, g: IntArray = IntArray(w * h), rng: Rng? = null,
                      found: MutableList<IntArray>? = null): Int {
        val of = HashMap<Int, MutableList<Run>>()
        for (run in runs) for (i in run.cells) of.getOrPut(i) { mutableListOf() } += run
        val cells = of.keys.toIntArray()
        fun fits(run: Run, i: Int, d: Int): Boolean {
            var used = 0; var sum = d; var left = 0
            for (j in run.cells) { val v = if (j == i) d else g[j]
                if (v == 0) left++ else { if (j != i && v == d) return false; used = used or (1 shl v); if (j != i) sum += v } }
            used = used or (1 shl d)
            if (run.sum == 0) return true // filling a pattern: no sums yet
            val rest = run.sum - sum
            if (left == 0) return rest == 0
            var lo = 0; var hi = 0; var k = 0
            for (v in 1..9) if (used and (1 shl v) == 0 && k < left) { lo += v; k++ }
            if (k < left) return false
            k = 0; for (v in 9 downTo 1) if (used and (1 shl v) == 0 && k < left) { hi += v; k++ }
            return rest in lo..hi
        }
        fun cands(i: Int) = (1..9).filter { d -> of.getValue(i).all { fits(it, i, d) } }
        fun go(lim: Int): Int {
            var best = -1; var bestC: List<Int> = emptyList()
            for (i in cells) if (g[i] == 0) { val c = cands(i); if (c.isEmpty()) return 0
                if (best < 0 || c.size < bestC.size) { best = i; bestC = c } }
            if (best < 0) { found?.add(g.copyOf()); return 1 }
            var n = 0
            for (d in if (rng != null) bestC.toMutableList().shuffleWith(rng) else bestC) {
                g[best] = d; n += go(lim - n); if (n >= lim) break
            }
            if (rng == null || n == 0) g[best] = 0 // a random filling keeps its digits
            return n
        }
        return go(limit)
    }

    /** A puzzle of w × h cells (first row and column included) */
    fun generate(seed: Long, w: Int, h: Int, maxRun: Int = 5, tries: Int = 400): Puzzle {
        val rng = Rng(seed)
        repeat(tries) {
            val white = pattern(w, h, rng, maxRun) ?: return@repeat
            val runs = runs(w, h, white)
            repeat(4) {
                val g = IntArray(w * h)
                runs.forEach { it.sum = 0 }
                if (count(w, h, runs, 1, g, rng) == 0) return@repeat
                runs.forEach { r -> r.sum = r.cells.sumOf { g[it] } }
                // digits given where two solutions differ, until there is one
                val given = IntArray(w * h)
                while (true) {
                    val sols = mutableListOf<IntArray>()
                    count(w, h, runs, 2, given.copyOf(), found = sols)
                    if (sols.size < 2) break
                    val diff = (0 until w * h).filter { sols[0][it] != sols[1][it] }
                    val i = diff[rng.next(diff.size) - 1]
                    given[i] = g[i]
                }
                if (given.count { it > 0 } > 5) return@repeat // too many: another filling
                val down = IntArray(w * h); val across = IntArray(w * h)
                for (r in runs) {
                    val first = r.cells[0]
                    if (r.cells[1] == first + 1) across[first - 1] = r.sum else down[first - w] = r.sum
                }
                return Puzzle(w, h, white, down, across, given)
            }
        }
        error("no kakuro")
    }
}
