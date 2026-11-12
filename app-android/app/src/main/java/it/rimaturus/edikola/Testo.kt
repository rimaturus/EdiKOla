// What Ascolta says, and in which voice: pure Kotlin (no Android), as knp_voce.lua.
package it.rimaturus.edikola

import java.io.DataOutputStream
import java.io.File
import java.io.FileOutputStream

object Testo {
    // Words that are frequent in one language and rare in the other
    private val IT = ("il lo la gli le di del della dei delle che è e per un una non con nel nella alla al sono anche più ma " +
        "come si ha da ci questo questa dopo tra").split(" ").toSet()
    private val EN = ("the and of to is that for on with was it are as by at from this have be has an not but he she they said " +
        "were their which will been who would").split(" ").toSet()
    private val word = Regex("\\p{L}+")

    /** "it" or "en", from the most common short words */
    fun lang(text: String): String {
        var it = 0; var en = 0
        for (m in word.findAll(text.lowercase())) {
            if (m.value in IT) it++ else if (m.value in EN) en++
        }
        return if (en > it) "en" else "it"
    }

    /** A piece to say: its text, voice, the article it belongs to (0-based), seconds of silence after it */
    data class Chunk(val text: String, val lang: String, val article: Int, val pause: Float)

    private const val CHUNK = 700 // characters: a few sentences, so a skip is quick
    private const val FIRST = 250 // an article's first piece is shorter, so its voice is ready soon after the title
    private val sentence = Regex("[^.!?]+[.!?]*\\s*")

    /** The intro (the paper's name and date), then each article's title, then its text in pieces. */
    fun chunks(articles: List<Pair<String, List<String>>>, intro: String?): List<Chunk> {
        val out = mutableListOf<Chunk>()
        if (intro != null) out += Chunk(intro, "it", 0, 1f)
        articles.forEachIndexed { i, (title, text) ->
            val lang = lang(title + " " + text.joinToString(" "))
            out += Chunk(title, lang, i, 0.8f)
            val piece = StringBuilder()
            var first = true
            fun flush() {
                if (piece.isNotEmpty()) { out += Chunk(piece.toString().trim(), lang, i, 0.5f); piece.clear() }
            }
            for (para in text) {
                val units = if (para.length > CHUNK) sentence.findAll(para).map { it.value }.toList() else listOf(para)
                for (u in units) {
                    if (piece.isNotEmpty() && piece.length + u.length > (if (first) FIRST else CHUNK)) { flush(); first = false }
                    piece.append(u).append('\n')
                }
            }
            flush()
            out[out.size - 1] = out.last().copy(pause = 1.5f) // between articles
        }
        return out
    }

    /** 16-bit mono WAV, with `pause` seconds of silence after the samples */
    fun writeWav(file: File, samples: FloatArray, rate: Int, pause: Float) {
        val n = samples.size + (pause * rate).toInt()
        DataOutputStream(FileOutputStream(file).buffered()).use { o ->
            fun le32(v: Int) { o.write(v and 255); o.write(v shr 8 and 255); o.write(v shr 16 and 255); o.write(v ushr 24) }
            fun le16(v: Int) { o.write(v and 255); o.write(v shr 8 and 255) }
            o.writeBytes("RIFF"); le32(36 + 2 * n); o.writeBytes("WAVE")
            o.writeBytes("fmt "); le32(16); le16(1); le16(1); le32(rate); le32(rate * 2); le16(2); le16(16)
            o.writeBytes("data"); le32(2 * n)
            for (i in 0 until n) {
                val s = if (i < samples.size) samples[i] else 0f
                le16((s.coerceIn(-1f, 1f) * 32767).toInt())
            }
        }
    }
}
