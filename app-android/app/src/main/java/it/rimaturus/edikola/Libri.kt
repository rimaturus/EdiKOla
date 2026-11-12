// I miei libri: EPUB and PDF files, added from the phone's files or shared from another app (LocalSend, a
// browser, the mail). EPUB opens in the reader, PDF page by page; the pen writes on both.
package it.rimaturus.edikola

import android.content.Context
import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChanged
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.jsoup.Jsoup
import java.io.File
import java.util.zip.ZipFile

object Libri {
    val dir: File get() = File(Repo.app.filesDir, "libri").apply { mkdirs() }
    val version = mutableIntStateOf(0) // bumped when the list changes

    fun list(): List<File> = dir.listFiles { f -> f.extension.lowercase() in setOf("epub", "pdf") }
        ?.sortedBy { it.name.lowercase() } ?: emptyList()

    /** Copies a document into the books; returns it, or null if it isn't an EPUB or a PDF */
    fun import(ctx: Context, uri: Uri): File? {
        var name = "libro"
        ctx.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) name = c.getString(0) ?: name
        }
        if (name == "libro") name = uri.lastPathSegment?.substringAfterLast('/') ?: name
        val type = ctx.contentResolver.getType(uri) ?: ""
        if (!name.contains('.')) name += if (type.contains("pdf")) ".pdf" else ".epub"
        if (name.substringAfterLast('.').lowercase() !in setOf("epub", "pdf")) return null
        val f = File(dir, name.replace(Regex("[/\\\\:]"), "_"))
        try {
            ctx.contentResolver.openInputStream(uri)?.use { i -> f.outputStream().use { i.copyTo(it) } } ?: return null
        } catch (e: Exception) {
            return null
        }
        version.intValue++
        return f
    }

    fun open(f: File) {
        if (f.extension.lowercase() == "pdf") Nav.go(Screen.Pdf(f))
        else epub(f)?.let { Nav.go(Screen.Read(it, Repo.position(it.key).first)) }
    }

    fun delete(f: File) {
        f.delete()
        File(Repo.app.cacheDir, "epub/" + f.nameWithoutExtension).deleteRecursively()
        version.intValue++
    }

    /** An EPUB as chapters of blocks: its spine, each chapter's headings, paragraphs and pictures */
    fun epub(f: File): ReaderDoc? = try {
        ZipFile(f).use { zip ->
            fun text(path: String) = zip.getEntry(path)?.let { e -> zip.getInputStream(e).use { String(it.readBytes()) } }
            val container = text("META-INF/container.xml") ?: return null
            val opfPath = Regex("full-path=\"([^\"]+)\"").find(container)?.groupValues?.get(1) ?: return null
            val opf = Jsoup.parse(text(opfPath) ?: return null, "", org.jsoup.parser.Parser.xmlParser())
            val base = opfPath.substringBeforeLast('/', "")
            fun resolve(dir: String, href: String): String {
                val parts = (if (dir.isEmpty()) emptyList() else dir.split('/')).toMutableList()
                for (p in java.net.URLDecoder.decode(href.substringBefore('#'), "UTF-8").split('/')) {
                    if (p == "..") parts.removeLastOrNull() else if (p != "." && p.isNotEmpty()) parts += p
                }
                return parts.joinToString("/")
            }
            val manifest = opf.select("manifest > item").associate { it.attr("id") to it.attr("href") }
            val title = opf.selectFirst("metadata > title, dc|title")?.text()?.takeIf { it.isNotBlank() } ?: f.nameWithoutExtension
            val images = File(Repo.app.cacheDir, "epub/" + f.nameWithoutExtension).apply { mkdirs() }
            val sections = mutableListOf<ReaderDoc.Section>()
            for (ref in opf.select("spine > itemref")) {
                val path = resolve(base, manifest[ref.attr("idref")] ?: continue)
                val html = text(path) ?: continue
                val dir = path.substringBeforeLast('/', "")
                val doc = Jsoup.parse(html)
                val blocks = mutableListOf<Block>()
                var heading: String? = null
                for (el in doc.body().select("h1, h2, h3, h4, p, li, blockquote, img, image")) {
                    when (el.normalName()) {
                        "img", "image" -> {
                            val src = el.attr("src").ifEmpty { el.attr("xlink:href").ifEmpty { el.attr("href") } }
                            if (src.isEmpty()) continue
                            val ip = resolve(dir, src)
                            val out = File(images, ip.replace('/', '_'))
                            if (!out.exists()) zip.getEntry(ip)?.let { e -> zip.getInputStream(e).use { i -> out.outputStream().use { i.copyTo(it) } } }
                            if (out.exists()) blocks += Block("img", out.absolutePath)
                        }
                        else -> {
                            if (el.parents().any { it.normalName() in setOf("p", "li", "blockquote") }) continue
                            val t = el.text().trim()
                            if (t.isEmpty()) continue
                            if (el.normalName().startsWith("h")) { if (heading == null) heading = t; blocks += Block("h", t) }
                            else blocks += Block("p", t)
                        }
                    }
                }
                if (blocks.isEmpty()) continue
                if (blocks.first().kind == "h") blocks.removeAt(0) // the reader shows it as the chapter's title
                sections += ReaderDoc.Section(heading ?: "Capitolo ${sections.size + 1}", blocks)
            }
            if (sections.isEmpty()) null else ReaderDoc("libro_" + f.name, title, sections, File("/"))
        }
    } catch (e: Exception) {
        null
    }
}

@Composable
fun LibriList() {
    val ctx = LocalContext.current
    val version by Libri.version
    val books = remember(version) { Libri.list() }
    var deleting by remember { mutableStateOf<File?>(null) }
    var failed by remember { mutableStateOf(false) }
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) Libri.import(ctx, uri)?.let { Libri.open(it) } ?: run { failed = true }
    }
    Box(Modifier.fillMaxSize()) {
        if (books.isEmpty()) {
            Text("Nessun libro ancora.\n\nTocca «Aggiungi» per scegliere un EPUB o un PDF dal telefono, oppure condividilo " +
                "con EdiKOla da un'altra app (LocalSend, il browser, la posta).", Modifier.padding(24.dp))
        }
        LazyColumn(contentPadding = PaddingValues(12.dp, 12.dp, 12.dp, 90.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(books, key = { it.name }) { f ->
                Card(Modifier.fillMaxWidth().clickable { Libri.open(f) },
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer)) {
                    Row(Modifier.padding(start = 12.dp), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                        Box(Modifier.width(6.dp).height(44.dp).background(MaterialTheme.colorScheme.primary, RoundedCornerShape(3.dp)))
                        Spacer(Modifier.width(10.dp))
                        Column(Modifier.weight(1f).padding(vertical = 10.dp)) {
                            Text(f.nameWithoutExtension, fontFamily = FontFamily.Serif, fontWeight = FontWeight.Bold)
                            Text(f.extension.uppercase(), style = MaterialTheme.typography.labelSmall)
                        }
                        IconButton(onClick = { deleting = f }) { Icon(Icons.Default.Delete, "Elimina") }
                    }
                }
            }
        }
        ExtendedFloatingActionButton(onClick = { pick.launch(arrayOf("application/epub+zip", "application/pdf")) },
            modifier = Modifier.align(androidx.compose.ui.Alignment.BottomEnd).padding(16.dp),
            icon = { Icon(Icons.Default.Add, null) }, text = { Text("Aggiungi") })
    }
    deleting?.let { f ->
        AlertDialog(onDismissRequest = { deleting = null }, title = { Text("Eliminare il libro?") }, text = { Text(f.name) },
            confirmButton = { TextButton(onClick = { Libri.delete(f); deleting = null }) { Text("Elimina") } },
            dismissButton = { TextButton(onClick = { deleting = null }) { Text("Annulla") } })
    }
    if (failed) AlertDialog(onDismissRequest = { failed = false }, text = { Text("Si possono aggiungere solo file EPUB e PDF.") },
        confirmButton = { TextButton(onClick = { failed = false }) { Text("OK") } })
}

/** A PDF page by page, the width of the screen; two fingers zoom and move; the pen writes on the pages */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PdfScreen(file: File) {
    val key = "pdf_" + file.name
    val renderer = remember(file) {
        try { PdfRenderer(ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)) } catch (e: Exception) { null }
    }
    DisposableEffect(renderer) { onDispose { renderer?.let { synchronized(it) { it.close() } } } }
    val ink = remember(key) { InkDoc.open(key) }
    val list = remember(key) { LazyListState(Repo.position(key).second) }
    DisposableEffect(key) { onDispose { Repo.savePosition(key, 0, list.firstVisibleItemIndex) } }
    var scale by remember { mutableFloatStateOf(1f) }
    var dx by remember { mutableFloatStateOf(0f) }
    var pen by remember { mutableStateOf(false) }

    Scaffold(topBar = {
        TopAppBar(
            title = { Text(file.nameWithoutExtension, maxLines = 1, fontFamily = FontFamily.Serif, fontWeight = FontWeight.Bold) },
            navigationIcon = { IconButton(onClick = { Nav.back() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Indietro") } },
            actions = {
                Box {
                    IconButton(onClick = { pen = true }) { Icon(Icons.Default.Edit, "Penna") }
                    DropdownMenu(expanded = pen, onDismissRequest = { pen = false }) {
                        InkDoc.INKS.forEachIndexed { i, c ->
                            DropdownMenuItem(text = { Text(InkDoc.INK_NAMES[i] + if (InkDoc.color.value == c) "  ✓" else "") },
                                onClick = { InkDoc.color.value = c; pen = false })
                        }
                        DropdownMenuItem(text = { Text("Annulla l'ultimo tratto") }, onClick = { ink.undo(); pen = false })
                        DropdownMenuItem(text = { Text("Cancella gli appunti") }, onClick = { ink.clear(); pen = false })
                    }
                }
            },
        )
    }) { pad ->
        if (renderer == null) {
            Text("Questo PDF non si apre.", Modifier.padding(pad).padding(24.dp))
            return@Scaffold
        }
        LazyColumn(
            Modifier.padding(pad).fillMaxSize()
                .pointerInput(Unit) { // two fingers: zoom and move sideways; one finger scrolls as usual
                    awaitEachGesture {
                        awaitFirstDown(requireUnconsumed = false)
                        do {
                            val ev = awaitPointerEvent()
                            if (ev.changes.count { it.pressed } >= 2) {
                                scale = (scale * ev.calculateZoom()).coerceIn(1f, 4f)
                                dx = (dx + ev.calculatePan().x).coerceIn(-(scale - 1) * size.width / 2, (scale - 1) * size.width / 2)
                                ev.changes.forEach { if (it.positionChanged()) it.consume() }
                            }
                        } while (ev.changes.any { it.pressed })
                    }
                }
                .graphicsLayer(scaleX = scale, scaleY = scale, translationX = dx),
            state = list,
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            items(renderer.pageCount) { i ->
                var bmp by remember { mutableStateOf<Bitmap?>(null) }
                // PdfRenderer opens one page at a time: every use holds its lock
                val ratio = remember(i) { synchronized(renderer) { renderer.openPage(i).use { it.width.toFloat() / it.height } } }
                LaunchedEffect(i) {
                    bmp = withContext(Dispatchers.IO) {
                        try {
                            synchronized(renderer) {
                                renderer.openPage(i).use { p ->
                                    val w = 1440
                                    val b = Bitmap.createBitmap(w, (w / ratio).toInt(), Bitmap.Config.ARGB_8888)
                                    b.eraseColor(android.graphics.Color.WHITE)
                                    p.render(b, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                                    b
                                }
                            }
                        } catch (e: Exception) {
                            null // the PDF was closed meanwhile
                        }
                    }
                }
                Box(Modifier.fillMaxWidth().aspectRatio(ratio).background(Color.White).ink(ink, "p$i", relative = true, dark = false)) {
                    bmp?.let { Image(it.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.FillBounds) }
                }
            }
        }
    }
}
