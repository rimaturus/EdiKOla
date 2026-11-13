// The reader: one article (or one chapter of a book) at a time, clean text and photos, the pen on the page.
package it.rimaturus.edikola

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.gestures.rememberTransformableState
import androidx.compose.foundation.gestures.transformable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import coil.compose.AsyncImage
import java.io.File

/** Something to read: sections (articles or chapters) of blocks; image blocks are file names under base */
class ReaderDoc(val key: String, val title: String, val sections: List<Section>, val base: File, val edition: Edition? = null) {
    class Section(val title: String, val blocks: List<Block>)

    companion object {
        fun of(ed: Edition) = ReaderDoc("giornale_${ed.paper}_${ed.date}", Repo.paper(ed.paper).name,
            ed.articles.map { Section(it.title, it.blocks) }, ed.dir, ed)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReaderScreen(doc: ReaderDoc, start: Int) {
    var section by rememberSaveable(doc.key) { mutableIntStateOf(start.coerceIn(0, doc.sections.size - 1)) }
    val font by Repo.fontSize.collectAsState()
    val ink = remember(doc.key) { InkDoc.open(doc.key) }
    val dark = isSystemInDarkTheme()
    var zoom by remember { mutableStateOf<File?>(null) }
    var pen by remember { mutableStateOf(false) }
    val sec = doc.sections[section]
    val books = doc.edition == null
    val list = remember(doc.key, section) {
        LazyListState(if (books && Repo.position(doc.key).first == section) Repo.position(doc.key).second else 0)
    }
    if (books) DisposableEffect(doc.key, section) {
        onDispose { Repo.savePosition(doc.key, section, list.firstVisibleItemIndex) }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text(doc.title, maxLines = 1, overflow = TextOverflow.Ellipsis, fontFamily = Reading, fontWeight = FontWeight.Bold)
                        Text("${if (books) "Capitolo" else "Articolo"} ${section + 1} di ${doc.sections.size}",
                            style = MaterialTheme.typography.labelMedium)
                    }
                },
                navigationIcon = { IconButton(onClick = { Nav.back() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Indietro") } },
                actions = {
                    TextButton(onClick = { Repo.setFont(font - 1) }) { Text("A−", fontSize = 15.sp) }
                    TextButton(onClick = { Repo.setFont(font + 1) }) { Text("A+", fontSize = 19.sp) }
                    Box {
                        IconButton(onClick = { pen = true }) { Icon(Icons.Default.Edit, "Penna") }
                        DropdownMenu(expanded = pen, onDismissRequest = { pen = false }) {
                            InkDoc.INKS.forEachIndexed { i, c ->
                                DropdownMenuItem(
                                    text = { Text(InkDoc.INK_NAMES[i] + if (InkDoc.color.value == c) "  ✓" else "") },
                                    leadingIcon = {
                                        Surface(Modifier.size(18.dp), shape = CircleShape,
                                            color = if (dark && i == 0) Color.White else Color(c)) {}
                                    },
                                    onClick = { InkDoc.color.value = c; pen = false },
                                )
                            }
                            HorizontalDivider()
                            DropdownMenuItem(text = { Text("Annulla l'ultimo tratto") }, onClick = { ink.undo(); pen = false })
                            DropdownMenuItem(text = { Text("Cancella gli appunti") }, onClick = { ink.clear(); pen = false })
                        }
                    }
                    if (doc.edition != null) IconButton(onClick = { Ascolta.listen(doc.edition, section); Nav.go(Screen.Player) }) {
                        Icon(androidx.compose.ui.res.painterResource(R.drawable.ic_headphones), "Ascolta da qui")
                    }
                },
            )
        },
        bottomBar = {
            Surface(tonalElevation = 2.dp) {
                Row(Modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = 8.dp, vertical = 4.dp),
                    horizontalArrangement = Arrangement.SpaceBetween) {
                    TextButton(onClick = { section-- }, enabled = section > 0) { Text("◀ Precedente") }
                    TextButton(onClick = { section++ }, enabled = section < doc.sections.size - 1) { Text("Successivo ▶") }
                }
            }
        },
    ) { pad ->
        LazyColumn(Modifier.padding(pad).fillMaxSize(), state = list, contentPadding = PaddingValues(horizontal = 18.dp, vertical = 12.dp)) {
            item(key = "title") {
                val tone = doc.edition?.let { LocalPalette.current.section(Repo.paper(it.paper).section) }
                Column(Modifier.fillMaxWidth().ink(ink, "$font:$section:t", dark = dark).padding(bottom = 14.dp)) {
                    Text(doc.title.uppercase() + (doc.edition?.let { " · " + Store.dateLabel(it.date) } ?: ""),
                        color = tone?.strong ?: MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(6.dp))
                    Text(sec.title, fontFamily = Display, fontWeight = FontWeight.Bold, fontSize = (font * 1.45f).sp,
                        lineHeight = (font * 1.8f).sp)
                    Spacer(Modifier.height(10.dp))
                    androidx.compose.foundation.layout.Box(Modifier.width(56.dp).height(4.dp)
                        .background(tone?.strong ?: MaterialTheme.colorScheme.primary, RoundedCornerShape(2.dp)))
                }
            }
            itemsIndexed(sec.blocks) { i, b ->
                val m = Modifier.fillMaxWidth().ink(ink, "$font:$section:$i", dark = dark)
                when (b.kind) {
                    "img" -> AsyncImage(File(doc.base, b.text), null,
                        m.padding(vertical = 8.dp).clip(MaterialTheme.shapes.small).clickable { zoom = File(doc.base, b.text) },
                        contentScale = ContentScale.FillWidth)
                    "h" -> Text(b.text, m.padding(top = 12.dp, bottom = 6.dp), fontFamily = Display,
                        fontWeight = FontWeight.Bold, fontSize = (font * 1.15f).sp, lineHeight = (font * 1.45f).sp)
                    else -> Text(b.text, m.padding(bottom = 12.dp), fontFamily = Reading, fontSize = font.sp,
                        lineHeight = (font * 1.55f).sp)
                }
            }
            item(key = "end") { Spacer(Modifier.height(24.dp)) }
        }
    }
    zoom?.let { f -> ZoomImage(f) { zoom = null } }
}

/** A photo full screen: pinch to zoom, drag to move, tap to close */
@Composable
fun ZoomImage(file: File, close: () -> Unit) {
    Dialog(onDismissRequest = close, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        var scale by remember { mutableFloatStateOf(1f) }
        var dx by remember { mutableFloatStateOf(0f) }
        var dy by remember { mutableFloatStateOf(0f) }
        val state = rememberTransformableState { z, pan, _ ->
            scale = (scale * z).coerceIn(1f, 6f); dx += pan.x; dy += pan.y
        }
        Box(Modifier.fillMaxSize().clickable(onClick = close), contentAlignment = Alignment.Center) {
            AsyncImage(file, null, Modifier.fillMaxWidth().transformable(state)
                .graphicsLayer(scaleX = scale, scaleY = scale, translationX = dx, translationY = dy),
                contentScale = ContentScale.Fit)
        }
    }
}
