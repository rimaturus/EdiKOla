// The reader: one article (or chapter) per page, swiped sideways; clean text and photos, the pen on the page.
package it.rimaturus.edikola

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.runtime.rememberCoroutineScope
import kotlinx.coroutines.launch
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

/** Something to read: sections (articles or chapters) of blocks; image blocks are file names under the section's
 *  base (or the document's). label: what goes above an article's title (its paper, its topic). */
class ReaderDoc(val key: String, val title: String, val sections: List<Section>, val base: File, val edition: Edition? = null) {
    class Section(val title: String, val blocks: List<Block>, val base: File? = null, val label: String? = null, val id: String = title)

    companion object {
        fun of(ed: Edition) = ReaderDoc("giornale_${ed.paper}_${ed.date}", Repo.paper(ed.paper).name,
            ed.articles.map { Section(it.title, it.blocks, id = it.link) }, ed.dir, ed)

        /** Today's stories, one article each, in the order of the home screen */
        fun oggi(stories: List<Story>) = ReaderDoc("oggi_" + Store.today(), "Le notizie di oggi",
            stories.map { s ->
                val r = s.main
                Section(r.article.title, r.article.blocks, r.ed.dir,
                    (s.papers.take(3).joinToString(" · ") + if (s.papers.size > 3) " +${s.papers.size - 3}" else "") + " — " + s.topic,
                    r.article.link)
            }, Store.root)
    }
}

/** The reader: one article (or chapter) per page, a swipe to the side for the next one. Little around the text:
 *  back, where you are, the type size, the voice, the pen. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReaderScreen(doc: ReaderDoc, start: Int) {
    val books = doc.edition == null && !doc.key.startsWith("oggi_")
    val first = if (books && Repo.position(doc.key).first in doc.sections.indices) Repo.position(doc.key).first else start
    val pager = rememberPagerState(first.coerceIn(0, doc.sections.size - 1)) { doc.sections.size }
    val scope = rememberCoroutineScope()
    val font by Repo.fontSize.collectAsState()
    val ink = remember(doc.key) { InkDoc.open(doc.key) }
    val dark = isSystemInDarkTheme()
    var zoom by remember { mutableStateOf<File?>(null) }
    var pen by remember { mutableStateOf(false) }
    var type by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text(doc.title, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.titleMedium)
                        Text("${pager.currentPage + 1} di ${doc.sections.size}", style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                },
                navigationIcon = { IconButton(onClick = { Nav.back() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Indietro") } },
                actions = {
                    Box {
                        TextButton(onClick = { type = true }) { Text("Aa", fontSize = 18.sp) }
                        DropdownMenu(expanded = type, onDismissRequest = { type = false }) {
                            DropdownMenuItem(text = { Text("Testo più grande") }, onClick = { Repo.setFont(font + 1) })
                            DropdownMenuItem(text = { Text("Testo più piccolo") }, onClick = { Repo.setFont(font - 1) })
                        }
                    }
                    if (!books) IconButton(onClick = { Ascolta.listen(doc, pager.currentPage); Nav.tab.intValue = 1; Nav.home() }) {
                        Icon(androidx.compose.ui.res.painterResource(R.drawable.ic_headphones), "Ascolta da qui")
                    }
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
                },
            )
        },
    ) { pad ->
        HorizontalPager(pager, Modifier.padding(pad).fillMaxSize(), beyondViewportPageCount = 1, key = { doc.sections[it].id }) { page ->
            val sec = doc.sections[page]
            val base = sec.base ?: doc.base
            val list = remember(doc.key, page) {
                LazyListState(if (books && Repo.position(doc.key).first == page) Repo.position(doc.key).second else 0)
            }
            if (books) DisposableEffect(doc.key, page) {
                onDispose { if (pager.currentPage == page) Repo.savePosition(doc.key, page, list.firstVisibleItemIndex) }
            }
            val tone = if (sec.label != null) MaterialTheme.colorScheme.primary
                else doc.edition?.let { LocalPalette.current.section(Repo.paper(it.paper).section).strong } ?: MaterialTheme.colorScheme.primary
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
                LazyColumn(Modifier.widthIn(max = 680.dp).fillMaxSize(), state = list,
                    contentPadding = PaddingValues(start = 22.dp, end = 22.dp, top = 8.dp, bottom = 24.dp)) {
                    item(key = "title") {
                        Column(Modifier.fillMaxWidth().ink(ink, "$font:${sec.id}:t", dark = dark).padding(bottom = 18.dp)) {
                            val label = sec.label ?: doc.edition?.let { Repo.paper(it.paper).name + " · " + Store.dateLabel(it.date) }
                            if (label != null) Text(label.uppercase(), color = tone, style = MaterialTheme.typography.labelMedium,
                                fontWeight = FontWeight.Bold, letterSpacing = 0.8.sp)
                            Spacer(Modifier.height(8.dp))
                            Text(sec.title, fontFamily = Display, fontWeight = FontWeight.Bold, fontSize = (font * 1.4f).sp,
                                lineHeight = (font * 1.75f).sp)
                        }
                    }
                    itemsIndexed(sec.blocks) { i, b ->
                        val m = Modifier.fillMaxWidth().ink(ink, "$font:${sec.id}:$i", dark = dark)
                        when (b.kind) {
                            "img" -> AsyncImage(File(base, b.text), null,
                                m.padding(vertical = 10.dp).clip(RoundedCornerShape(10.dp)).clickable { zoom = File(base, b.text) },
                                contentScale = ContentScale.FillWidth)
                            "h" -> Text(b.text, m.padding(top = 14.dp, bottom = 6.dp), fontFamily = Reading,
                                fontWeight = FontWeight.Bold, fontSize = (font * 1.1f).sp, lineHeight = (font * 1.45f).sp)
                            else -> Text(b.text, m.padding(bottom = 14.dp), fontFamily = Reading, fontSize = font.sp,
                                lineHeight = (font * 1.6f).sp)
                        }
                    }
                    if (page < doc.sections.size - 1) item(key = "next") {
                        HorizontalDivider(Modifier.padding(top = 12.dp, bottom = 4.dp))
                        Column(Modifier.fillMaxWidth().clickable { scope.launch { pager.animateScrollToPage(page + 1) } }.padding(vertical = 14.dp)) {
                            Text(if (books) "CAPITOLO SUCCESSIVO  →" else "PROSSIMA NOTIZIA  →", color = tone,
                                style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold)
                            Spacer(Modifier.height(4.dp))
                            Text(doc.sections[page + 1].title, fontFamily = Reading, fontWeight = FontWeight.SemiBold,
                                maxLines = 3, overflow = TextOverflow.Ellipsis)
                        }
                    }
                }
            }
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
