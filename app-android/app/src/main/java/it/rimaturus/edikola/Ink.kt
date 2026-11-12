// The pen writes straight on what you read: articles, books, PDF pages. Only a stylus draws (fingers scroll and
// tap as usual); its eraser end, or its button held, erases whole strokes. Pressure makes the line thicker.
// Ink belongs to a block of text (or a PDF page) and is kept per document in files/appunti/<doc>.json.
package it.rimaturus.edikola

import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke as DrawStroke
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.input.pointer.PointerType
import androidx.compose.ui.input.pointer.isSecondaryPressed
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.runtime.remember
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** points: x, y, pressure, ...; x and y in dp from the block's corner, or 0..1 of the page when `relative` */
class InkStroke(val color: Int, val points: FloatArray)

class InkDoc(private val file: File) {
    val blocks = mutableStateMapOf<String, List<InkStroke>>()
    private val order = mutableListOf<String>() // block of each stroke, newest last: for "Annulla"

    init {
        try {
            val o = JSONObject(file.readText())
            for (k in o.keys()) {
                val arr = o.getJSONArray(k)
                blocks[k] = (0 until arr.length()).map { i ->
                    val s = arr.getJSONObject(i)
                    val p = s.getJSONArray("p")
                    InkStroke(s.getInt("c"), FloatArray(p.length()) { p.getDouble(it).toFloat() })
                }
            }
        } catch (e: Exception) { /* no ink yet */ }
    }

    private fun save() {
        val o = JSONObject()
        for ((k, list) in blocks) if (list.isNotEmpty()) o.put(k, JSONArray().apply {
            list.forEach { s -> put(JSONObject().put("c", s.color).put("p", JSONArray().apply { s.points.forEach { put(it.toDouble()) } })) }
        })
        file.parentFile?.mkdirs()
        file.writeText(o.toString())
    }

    fun add(block: String, s: InkStroke) {
        blocks[block] = (blocks[block] ?: emptyList()) + s
        order += block
        save()
    }

    /** removes the strokes passing within r of (x, y) */
    fun erase(block: String, x: Float, y: Float, r: Float) {
        val list = blocks[block] ?: return
        val left = list.filter { s ->
            var i = 0
            var hit = false
            while (i < s.points.size && !hit) {
                val dx = s.points[i] - x; val dy = s.points[i + 1] - y
                hit = dx * dx + dy * dy < r * r
                i += 3
            }
            !hit
        }
        if (left.size != list.size) { blocks[block] = left; save() }
    }

    fun undo() {
        val k = order.removeLastOrNull() ?: blocks.keys.lastOrNull() ?: return
        blocks[k] = (blocks[k] ?: return).dropLast(1)
        save()
    }

    fun clear() {
        blocks.clear()
        order.clear()
        save()
    }

    companion object {
        val INKS = listOf(0xFF000000.toInt(), 0xFF1A3FA8.toInt(), 0xFFC62828.toInt(), 0xFF2E7D32.toInt())
        val INK_NAMES = listOf("Nero", "Blu", "Rosso", "Verde")
        val color = mutableStateOf(INKS[0])
        fun open(doc: String) = InkDoc(File(Repo.app.filesDir, "appunti/" + doc.replace(Regex("[^\\w.-]"), "_") + ".json"))
    }
}

/**
 * Draws the block's ink and lets a stylus write on it. relative: points are fractions of the size (PDF pages).
 * dark: ink black becomes white, so it stays visible on a dark page.
 */
@OptIn(ExperimentalComposeUiApi::class)
fun Modifier.ink(doc: InkDoc, block: String, relative: Boolean = false, dark: Boolean = false): Modifier = composed {
    val live = remember { mutableStateOf<FloatArray?>(null) }
    this
        .pointerInput(doc, block) {
            awaitEachGesture {
                val down = awaitFirstDown(requireUnconsumed = false)
                if (down.type != PointerType.Stylus && down.type != PointerType.Eraser) return@awaitEachGesture
                val erasing = down.type == PointerType.Eraser || currentEvent.buttons.isSecondaryPressed
                down.consume()
                val w = size.width.toFloat(); val h = size.height.toFloat()
                fun conv(o: Offset) = if (relative) Offset(o.x / w, o.y / h) else Offset(o.x / density, o.y / density)
                val r = if (relative) 12 * density / w else 12f
                val pts = ArrayList<Float>()
                fun add(o: Offset, p: Float) {
                    val c = conv(o)
                    if (erasing) doc.erase(block, c.x, c.y, r) else { pts += c.x; pts += c.y; pts += p; live.value = pts.toFloatArray() }
                }
                add(down.position, down.pressure)
                while (true) {
                    val ev = awaitPointerEvent()
                    val ch = ev.changes.firstOrNull { it.id == down.id } ?: break
                    ch.historical.forEach { add(it.position, ch.pressure) }
                    add(ch.position, ch.pressure)
                    ch.consume()
                    if (!ch.pressed) break
                }
                live.value = null
                if (!erasing && pts.size >= 6) doc.add(block, InkStroke(InkDoc.color.value, pts.toFloatArray()))
            }
        }
        .drawWithContent {
            drawContent()
            val sx = if (relative) size.width else density
            val sy = if (relative) size.height else density
            val strokes = (doc.blocks[block] ?: emptyList()) + listOfNotNull(live.value?.let { InkStroke(InkDoc.color.value, it) })
            for (s in strokes) {
                val p = s.points
                if (p.size < 6) continue
                var col = Color(s.color)
                if (dark && s.color == InkDoc.INKS[0]) col = Color.White
                // a path per pair of points, so the pressure can change the width along the line
                for (i in 3 until p.size step 3) {
                    val path = Path().apply { moveTo(p[i - 3] * sx, p[i - 2] * sy); lineTo(p[i] * sx, p[i + 1] * sy) }
                    val width = (1.2f + 2.8f * p[i + 2].coerceIn(0f, 1f)) * density
                    drawPath(path, col, style = DrawStroke(width = width, cap = StrokeCap.Round))
                }
            }
        }
}
