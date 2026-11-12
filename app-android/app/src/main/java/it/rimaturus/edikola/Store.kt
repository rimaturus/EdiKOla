// Downloads newspapers and keeps their editions on the phone, as knp_build.lua: one JSON file per paper and day,
// the photos next to it. Only articles not downloaded before use the network; the last 3 days are kept.
package it.rimaturus.edikola

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

data class Article(
    val title: String,
    val link: String,
    val blocks: List<Block>,
    val titleIt: String? = null, // Italian title and brief of an English article, for the Sommario
    val briefIt: String? = null,
) {
    val brief: String get() = Extract.brief(blocks)
    val paragraphs: List<String> get() = blocks.filter { it.kind != "img" }.map { it.text }
}

data class Edition(val paper: String, val date: String, val articles: List<Article>, val dir: File) {
    val cover: File? get() = articles.firstNotNullOfOrNull { a -> a.blocks.firstOrNull { it.kind == "img" } }?.let { File(dir, it.text) }
    val headline: String get() = articles.firstOrNull()?.title.orEmpty()
}

object Store {
    lateinit var root: File
    private const val KEEP_DAYS = 3
    private const val MAX_IMAGES = 3
    private const val MAX_IMAGE_BYTES = 1500 * 1024
    private const val UA = "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Mobile Safari/537.36"

    private val GIORNI = listOf("domenica", "lunedì", "martedì", "mercoledì", "giovedì", "venerdì", "sabato")
    private val MESI = listOf("gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno", "luglio", "agosto",
        "settembre", "ottobre", "novembre", "dicembre")

    fun today(): String = SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).format(Date())

    /** "giovedì 12 novembre 2026" for "2026-11-12" */
    fun dateLabel(date: String = today()): String {
        val c = Calendar.getInstance()
        c.time = SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).parse(date) ?: Date()
        return "${GIORNI[c.get(Calendar.DAY_OF_WEEK) - 1]} ${c.get(Calendar.DAY_OF_MONTH)} ${MESI[c.get(Calendar.MONTH)]} ${c.get(Calendar.YEAR)}"
    }

    private fun md5(s: String) = MessageDigest.getInstance("MD5").digest(s.toByteArray()).joinToString("") { "%02x".format(it) }

    fun get(url: String): ByteArray? {
        var u = url
        repeat(5) { // follow redirects ourselves: HttpURLConnection won't across http/https
            val c = (URL(u).openConnection() as HttpURLConnection).apply {
                instanceFollowRedirects = false
                connectTimeout = 15000
                readTimeout = 20000
                setRequestProperty("User-Agent", UA)
                setRequestProperty("Accept-Language", "it-IT,it;q=0.9,en;q=0.8")
            }
            try {
                val code = c.responseCode
                if (code in 300..399) {
                    u = URL(URL(u), c.getHeaderField("Location") ?: return null).toString()
                } else if (code == 200) {
                    return c.inputStream.use { it.readBytes() }
                } else return null
            } catch (e: Exception) {
                return null
            } finally {
                c.disconnect()
            }
        }
        return null
    }

    // ---- JSON

    private fun blocksJson(blocks: List<Block>) = JSONArray().apply {
        blocks.forEach { put(JSONObject().put("k", it.kind).put("t", it.text)) }
    }

    private fun articleJson(a: Article) = JSONObject().put("title", a.title).put("link", a.link)
        .put("blocks", blocksJson(a.blocks)).put("titleIt", a.titleIt ?: JSONObject.NULL).put("briefIt", a.briefIt ?: JSONObject.NULL)

    private fun articleOf(o: JSONObject): Article {
        val bs = o.getJSONArray("blocks")
        return Article(
            o.getString("title"), o.optString("link"),
            (0 until bs.length()).map { bs.getJSONObject(it).let { b -> Block(b.getString("k"), b.getString("t")) } },
            o.optString("titleIt").takeIf { !o.isNull("titleIt") && it.isNotEmpty() },
            o.optString("briefIt").takeIf { !o.isNull("briefIt") && it.isNotEmpty() },
        )
    }

    private fun writeAtomic(f: File, text: String) {
        val tmp = File(f.path + ".tmp")
        tmp.writeText(text)
        tmp.renameTo(f)
    }

    // ---- editions

    private fun dir(paper: Paper) = File(root, paper.id)

    /** Newest edition on the phone */
    fun latest(paper: Paper): Edition? {
        val f = dir(paper).listFiles { f -> f.name.matches(Regex("\\d{4}-\\d{2}-\\d{2}\\.json")) }?.maxByOrNull { it.name } ?: return null
        return load(paper, f)
    }

    private fun load(paper: Paper, f: File): Edition? = try {
        val o = JSONObject(f.readText())
        val arts = o.getJSONArray("articles")
        Edition(paper.id, o.getString("date"), (0 until arts.length()).map { articleOf(arts.getJSONObject(it)) }, f.parentFile!!)
    } catch (e: Exception) {
        null
    }

    private fun imageExt(d: ByteArray): String? = when {
        d.size > 3 && d[0] == 0xFF.toByte() && d[1] == 0xD8.toByte() -> "jpg"
        d.size > 8 && d[0] == 0x89.toByte() && d[1] == 'P'.code.toByte() -> "png"
        d.size > 4 && String(d, 0, 4, Charsets.ISO_8859_1) == "GIF8" -> "gif"
        d.size > 12 && String(d, 0, 4, Charsets.ISO_8859_1) == "RIFF" && String(d, 8, 4, Charsets.ISO_8859_1) == "WEBP" -> "webp"
        else -> null
    }

    // One article (images downloaded next to the edition), or null when it isn't a real free article
    private fun download(item: Extract.FeedItem, key: String, img: File): Article? {
        var blocks = get(item.link)?.let { Extract.article(Extract.decode(it), item.link) } ?: emptyList()
        if (Extract.length(blocks) < 400) blocks = Extract.article(Extract.feedHTML(item.content), item.link)
        if (Extract.length(blocks) < 400) return null
        var n = 0
        val out = blocks.mapNotNull { b ->
            if (b.kind != "img") return@mapNotNull b
            if (n >= MAX_IMAGES) return@mapNotNull null
            val data = get(b.text)?.takeIf { it.size <= MAX_IMAGE_BYTES } ?: return@mapNotNull null
            val ext = imageExt(data) ?: return@mapNotNull null
            n++
            val name = "img/${key}_$n.$ext"
            File(img.parentFile, name).writeBytes(data)
            Block("img", name)
        }
        return Article(item.title, item.link, out)
    }

    /** Italian title and brief of an English article (Google Translate's free endpoint), or null when offline */
    private fun italian(title: String, brief: String, from: String): Pair<String, String>? = try {
        val q = URLEncoder.encode("$title\n$brief", "UTF-8")
        val data = get("https://translate.googleapis.com/translate_a/single?client=gtx&sl=$from&tl=it&dt=t&q=$q")
        val parts = JSONArray(String(data!!)).getJSONArray(0)
        val text = (0 until parts.length()).joinToString("") { parts.getJSONArray(it).getString(0) }
        val i = text.indexOf('\n')
        if (i > 0) text.substring(0, i).trim() to text.substring(i + 1).trim() else null
    } catch (e: Exception) {
        null
    }

    /** Builds today's edition of a paper. Returns null and a reason when it can't. */
    fun build(paper: Paper): Pair<Edition?, String?> {
        val xml = get(paper.feed) ?: return null to "giornale non raggiungibile"
        val items = Extract.feed(Extract.decode(xml))
        val d = dir(paper)
        val cache = File(d, "cache").apply { mkdirs() }
        val img = File(d, "img").apply { mkdirs() }
        val articles = mutableListOf<Article>()
        val used = mutableSetOf<String>()
        for (item in items.take(paper.max * 2)) { // spare tries: videos and teasers are skipped
            if (articles.size >= paper.max) break
            val key = md5(item.link)
            if (!used.add(key)) continue
            val cf = File(cache, "$key.json")
            var a: Article? = null
            var skip = false
            if (cf.exists()) {
                try {
                    val o = JSONObject(cf.readText())
                    if (o.optBoolean("skip")) skip = true else a = articleOf(o)
                } catch (e: Exception) { /* a broken cache file: download again */ }
            }
            if (a == null && !skip) {
                a = download(item, key, img)
                if (a == null) { writeAtomic(cf, JSONObject().put("skip", true).toString()); continue }
            }
            var art: Article = a ?: continue
            if (paper.lang != null && paper.lang != "it" && art.titleIt == null) {
                val it2 = italian(art.title, art.brief, paper.lang)
                if (it2 != null) art = art.copy(titleIt = it2.first, briefIt = it2.second)
            }
            writeAtomic(cf, articleJson(art).toString())
            articles += art
        }
        cache.listFiles()?.forEach { if (it.name.substringBefore('.') !in used) it.delete() }
        if (articles.isEmpty()) return null to "nessun articolo gratuito trovato"
        val date = today()
        val o = JSONObject().put("paper", paper.id).put("date", date)
            .put("articles", JSONArray().apply { articles.forEach { put(articleJson(it)) } })
        writeAtomic(File(d, "$date.json"), o.toString())
        prune(paper, used)
        return Edition(paper.id, date, articles, d) to null
    }

    // The last few editions; photos no edition or cached article uses any more go
    private fun prune(paper: Paper, cached: Set<String>) {
        val d = dir(paper)
        val eds = d.listFiles { f -> f.name.matches(Regex("\\d{4}-\\d{2}-\\d{2}\\.json")) }?.sortedByDescending { it.name } ?: return
        eds.drop(KEEP_DAYS).forEach { it.delete() }
        val keep = mutableSetOf<String>()
        for (f in eds.take(KEEP_DAYS)) load(paper, f)?.articles?.forEach { a -> a.blocks.filter { it.kind == "img" }.forEach { keep += File(it.text).name } }
        File(d, "img").listFiles()?.forEach { if (it.name !in keep && it.name.substringBefore('_') !in cached) it.delete() }
    }
}
