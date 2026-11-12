// RSS/Atom parsing and article extraction down to plain paragraphs, subheads and images, as knp_extract.lua.
// Extraction is a small readability: every <p> gives its text length to its ancestors (slowly decaying,
// 6 levels up); the best-scored element is the article body. Only text and images survive.
package it.rimaturus.edikola

import org.jsoup.Jsoup
import org.jsoup.nodes.Element
import org.jsoup.parser.Parser
import java.net.URL
import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.Charset
import java.nio.charset.CodingErrorAction
import java.util.IdentityHashMap

/** kind: "p" paragraph, "h" subhead, "img" image (text = its URL, or file name once downloaded) */
data class Block(val kind: String, val text: String)

object Extract {
    data class FeedItem(val title: String, val link: String, val content: String)

    private val DROP = "script,style,noscript,svg,iframe,form,button,nav,footer,header,aside,template,select,dialog," +
        "video,audio,object,canvas,figcaption,time"
    private val BLOCK = setOf("p", "h2", "h3", "h4", "li", "blockquote")
    private val JUNK = listOf("comment", "share", "social", "related", "promo", "newsletter", "subscri", "sidebar", "cookie",
        "consent", "banner", "recirc", "outbrain", "taboola", "advert", "sponsor", "mostread", "most-read", "paywall", "byline",
        "breadcrumb", "caption-credit", "read-more", "readmore", "tags", "toolbar").map { Regex(Regex.escape(it)) } +
        listOf(Regex("^ad$"), Regex("^ad[-_]"), Regex("[-_]ad$"), Regex("[-_]ad[-_]"))
    private const val TARGET_W = 1080 // srcset: the candidate closest to a phone's width

    /** Pages that aren't valid UTF-8 (Corriere serves Latin-1) are read as Windows-1252 */
    fun decode(bytes: ByteArray): String {
        val dec = Charsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)
        return try {
            dec.decode(ByteBuffer.wrap(bytes)).toString()
        } catch (e: CharacterCodingException) {
            String(bytes, Charset.forName("windows-1252"))
        }
    }

    /** RSS 2.0 / Atom */
    fun feed(xml: String): List<FeedItem> {
        val doc = Jsoup.parse(xml, "", Parser.xmlParser())
        val out = mutableListOf<FeedItem>()
        for (el in doc.select("item, entry")) {
            var link = el.selectFirst("link")?.text()?.trim().orEmpty()
            if (link.isEmpty()) {
                link = el.select("link").firstOrNull { it.attr("rel") == "alternate" }?.attr("href")
                    ?: el.selectFirst("link[href]")?.attr("href").orEmpty()
            }
            val rawTitle = el.selectFirst("title")?.wholeText() ?: continue
            if (link.isEmpty()) continue
            val content = listOf("content|encoded", "content", "description", "summary")
                .firstNotNullOfOrNull { el.selectFirst(it)?.wholeText() } ?: ""
            out += FeedItem(Jsoup.parse(rawTitle).text(), link, content)
        }
        return out
    }

    /** Feed descriptions are usually entity-escaped HTML */
    fun feedHTML(content: String): String =
        if (content.contains("&lt;")) Parser.unescapeEntities(content, false) else content

    private fun isJunk(el: Element): Boolean {
        if (el.attr("aria-hidden") == "true" || el.hasAttr("hidden")) return true
        val names = (el.className() + " " + el.id()).lowercase()
        return names.split(Regex("\\s+")).any { w -> w.isNotEmpty() && JUNK.any { it.containsMatchIn(w) } }
    }

    private fun bestSrc(img: Element, base: String): String? {
        val srcset = img.attr("srcset").ifEmpty { img.attr("data-srcset") }
        var src: String? = null
        if (srcset.isNotEmpty()) {
            src = Regex("(\\S+)\\s+(\\d+)w").findAll(srcset)
                .minByOrNull { Math.abs(it.groupValues[2].toInt() - TARGET_W) }?.groupValues?.get(1)
        }
        if (src == null) {
            src = listOf("data-src", "data-lazy-src", "data-original", "src").map { img.attr(it) }.firstOrNull { it.isNotEmpty() }
        }
        if (src == null) return null
        return try { URL(URL(base), Parser.unescapeEntities(src, true)).toString() } catch (e: Exception) { null }
    }

    private fun usableImage(img: Element, src: String?): Boolean {
        if (src == null || src.startsWith("data:") || src.lowercase().contains(".svg")) return false
        val w = img.attr("width").toIntOrNull()
        val h = img.attr("height").toIntOrNull()
        if ((w != null && w < 120) || (h != null && h < 120)) return false // icons, logos, tracking pixels
        val l = src.lowercase()
        return !(l.contains("logo") || l.contains("icon") || l.contains("pixel"))
    }

    private class Item(val kind: String, val text: String, val node: Element)

    /** The article as blocks; base resolves relative image addresses */
    fun article(html: String, base: String): List<Block> {
        val doc = Jsoup.parse(html, base)
        doc.select(DROP).remove()
        val score = IdentityHashMap<Element, Double>()
        val junk = IdentityHashMap<Element, Boolean>()
        fun junkOf(e: Element) = junk.getOrPut(e) { isJunk(e) }
        val items = mutableListOf<Item>()

        fun walk(el: Element, inBlock: Boolean) {
            for (child in el.children()) {
                val name = child.normalName()
                if (name == "img") {
                    val src = bestSrc(child, base)
                    if (usableImage(child, src)) items += Item("img", src!!, el)
                } else if (!inBlock && name in BLOCK) {
                    val txt = child.text().trim()
                    if (txt.length > 1) {
                        items += Item(if (name.startsWith("h")) "h" else "p", txt, child)
                        if (name == "p" && txt.length >= 25 && !junkOf(child)) {
                            // slow decay up 6 levels: some sites wrap each paragraph in its own divs
                            var n = child.parent()
                            for (k in 1..6) {
                                if (n == null) break
                                if (!junkOf(n)) score[n] = (score[n] ?: 0.0) + txt.length * (1 - (k - 1) * 0.12)
                                n = n.parent()
                            }
                        }
                    }
                    walk(child, true)
                } else {
                    walk(child, inBlock)
                }
            }
        }
        walk(doc.body() ?: return emptyList(), false)

        val best = score.maxByOrNull { it.value }?.key ?: return emptyList()
        // keep blocks inside the body, unless something between them and the body is junk
        val out = mutableListOf<Block>()
        val seen = mutableSetOf<String>()
        for (it in items) {
            var n: Element? = it.node
            var bad = false
            while (n != null && n !== best) { bad = bad || junkOf(n); n = n.parent() }
            if (n === best && !bad && !(it.kind == "p" && it.text.length < 20) && seen.add(it.text)) out += Block(it.kind, it.text)
        }
        return out
    }

    /** Characters of body text, to tell a real article from a teaser */
    fun length(blocks: List<Block>) = blocks.filter { it.kind == "p" }.sumOf { it.text.length }

    /** The opening sentences of an article, about max characters: news put the gist first */
    fun brief(blocks: List<Block>, max: Int = 280): String {
        var out = ""
        for (b in blocks) {
            if (b.kind != "p") continue
            out = if (out.isEmpty()) b.text else "$out ${b.text}"
            if (out.length >= max * 0.6) break
        }
        if (out.length <= max) return out
        val cut = out.substring(0, max)
        val m = Regex("^(.*[.!?])\\s").find(cut)
        if (m != null && m.groupValues[1].length > max / 3) return m.groupValues[1]
        return cut.replace(Regex("\\s+\\S*$"), "") + "…"
    }
}
