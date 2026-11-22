// The home screen, three tabs: Oggi (today's news, by topic or by paper), Radio, Giochi e libri. Then a paper's
// page, the settings, and the bar of what's playing.
// Oggi by topic: the story most papers cover on top ("in primo piano"), the other big stories of the day, then
// every topic with its stories; a story told by several papers appears once. Tapping one opens the reader on it,
// and a swipe goes on to the next one, in the same order.
package it.rimaturus.edikola

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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen() {
    val tab by Nav.tab
    val progress by Repo.progress.collectAsState()
    val message by Repo.message.collectAsState()
    val snack = remember { SnackbarHostState() }
    LaunchedEffect(message) {
        message?.let { snack.showSnackbar(it); Repo.message.value = null }
    }
    Scaffold(
        topBar = {
            Column {
                TopAppBar(
                    title = {
                        Column {
                            Text(listOf("EdiKOla", "Radio", "Giochi e libri")[tab], style = MaterialTheme.typography.headlineMedium,
                                fontWeight = FontWeight.Black)
                            Text(Store.dateLabel().replaceFirstChar { it.uppercase() }, style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    },
                    actions = {
                        if (tab == 0) {
                            IconButton(onClick = { Repo.update(PAPERS.filter { it.id in Repo.selected.value }) },
                                enabled = progress == null) { Icon(Icons.Default.Refresh, "Aggiorna") }
                            IconButton(onClick = { Nav.go(Screen.Catalog) }) { Icon(Icons.Default.Settings, "Impostazioni") }
                        }
                    },
                )
                progress?.let {
                    LinearProgressIndicator(Modifier.fillMaxWidth())
                    Text(it, Modifier.padding(horizontal = 16.dp, vertical = 2.dp), style = MaterialTheme.typography.labelMedium)
                }
            }
        },
        bottomBar = {
            Column {
                if (tab != 1) MiniPlayer()
                NavigationBar {
                    val items = listOf("Oggi" to R.drawable.ic_newspaper, "Radio" to R.drawable.ic_podcasts,
                        "Giochi e libri" to R.drawable.ic_extension)
                    items.forEachIndexed { i, (label, icon) ->
                        NavigationBarItem(selected = tab == i, onClick = { Nav.tab.intValue = i },
                            icon = { Icon(painterResource(icon), label) }, label = { Text(label) })
                    }
                }
            }
        },
        snackbarHost = { SnackbarHost(snack) },
    ) { pad ->
        Box(Modifier.padding(pad)) {
            when (tab) {
                0 -> Oggi()
                1 -> RadioScreen()
                else -> Svago()
            }
        }
    }
}

/** Two choices side by side */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun Choice(labels: List<String>, selected: Int, onSelect: (Int) -> Unit) {
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp)) {
        labels.forEachIndexed { i, l ->
            SegmentedButton(selected = i == selected, onClick = { onSelect(i) }, shape = SegmentedButtonDefaults.itemShape(i, labels.size),
                icon = {}) { Text(l) }
        }
    }
}

@Composable
fun Oggi() {
    var byPaper by rememberSaveable { mutableStateOf(0) }
    Column {
        Choice(listOf("Per argomento", "Per giornale"), byPaper) { byPaper = it }
        if (byPaper == 1) PerGiornale() else PerArgomento()
    }
}

/** Small capitals above a group */
@Composable
fun Kicker(text: String, color: Color = MaterialTheme.colorScheme.onSurfaceVariant, modifier: Modifier = Modifier) {
    Text(text.uppercase(), modifier, color = color, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold,
        letterSpacing = 1.sp)
}

private fun sources(s: Story) = when (s.papers.size) {
    1 -> s.papers[0]
    2 -> s.papers.joinToString(" e ")
    else -> "${s.papers[0]}, ${s.papers[1]} e altri ${s.papers.size - 2}"
}

@Composable
fun PerArgomento() {
    val stories by Notizie.oggi.collectAsState()
    val progress by Repo.progress.collectAsState()
    val pal = LocalPalette.current
    if (stories.isEmpty()) {
        Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
            Text(if (progress != null) "Scarico le notizie di oggi…" else "Ancora nessuna notizia di oggi.\nTocca Aggiorna in alto.")
        }
        return
    }
    val lay = remember(stories) { Layout(stories) }
    val hero = lay.hero; val big = lay.big; val byTopic = lay.byTopic; val topics = lay.topics; val order = lay.order
    val doc = remember(stories) { ReaderDoc.oggi(order) }
    fun open(s: Story) = Nav.go(Screen.Read(doc, order.indexOf(s)))
    var expanded by remember { mutableStateOf(setOf<String>()) }

    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(start = 18.dp, end = 18.dp, bottom = 24.dp)) {
        item(key = "hero") {
            Column(Modifier.fillMaxWidth().clickable { open(hero) }.padding(top = 8.dp, bottom = 18.dp)) {
                Kicker("In primo piano · " + hero.topic, pal.topic(hero.topic))
                Spacer(Modifier.height(10.dp))
                hero.main.image?.let {
                    AsyncImage(it, null, Modifier.fillMaxWidth().aspectRatio(16 / 9f).clip(RoundedCornerShape(14.dp)),
                        contentScale = ContentScale.Crop)
                    Spacer(Modifier.height(12.dp))
                }
                Text(hero.main.title, fontFamily = Display, fontWeight = FontWeight.Bold, fontSize = 26.sp, lineHeight = 32.sp)
                Spacer(Modifier.height(8.dp))
                Text(hero.main.brief, style = MaterialTheme.typography.bodyLarge, maxLines = 4, overflow = TextOverflow.Ellipsis,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(8.dp))
                Text(sources(hero), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        if (big.isNotEmpty()) {
            item(key = "big") { HorizontalDivider(); Kicker("Le notizie del giorno", modifier = Modifier.padding(top = 18.dp, bottom = 4.dp)) }
            items(big) { s -> StoryRow(s, pal.topic(s.topic), s.topic) { open(s) } }
        }
        for (t in topics) {
            val list = byTopic.getValue(t)
            val all = t in expanded || list.size <= 5
            item(key = "t$t") {
                Row(Modifier.padding(top = 26.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(width = 4.dp, height = 22.dp).background(pal.topic(t), RoundedCornerShape(2.dp)))
                    Spacer(Modifier.width(10.dp))
                    Text(t, style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
                    Text("${list.size}", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            items(if (all) list else list.take(4)) { s -> StoryRow(s, pal.topic(t), null) { open(s) } }
            if (!all) item(key = "m$t") {
                TextButton(onClick = { expanded = expanded + t }) { Text("Altre ${list.size - 4} notizie", color = pal.topic(t)) }
            }
        }
    }
}

/** A story in a list: its title, and who tells it */
@Composable
fun StoryRow(s: Story, color: Color, topic: String?, onClick: () -> Unit) {
    Column(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 12.dp)) {
        Text(s.main.title, fontFamily = Reading, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, lineHeight = 23.sp,
            maxLines = 4, overflow = TextOverflow.Ellipsis)
        Spacer(Modifier.height(4.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (topic != null) {
                Text(topic, style = MaterialTheme.typography.labelMedium, color = color, fontWeight = FontWeight.Bold)
                Text("  ·  ", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text(sources(s), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
}

/** The papers on the shelves, each with its first headlines */
@Composable
fun PerGiornale() {
    val editions by Repo.editions.collectAsState()
    val selected by Repo.selected.collectAsState()
    val pal = LocalPalette.current
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(start = 18.dp, end = 18.dp, bottom = 24.dp)) {
        for (sec in SECTIONS) {
            val papers = PAPERS.filter { it.section == sec.id && it.id in selected }
            if (papers.isEmpty()) continue
            item(key = "h" + sec.id) { Kicker(sec.name, pal.section(sec.id).strong, Modifier.padding(top = 20.dp, bottom = 2.dp)) }
            items(papers, key = { it.id }) { p -> PaperRow(p, editions[p.id], pal.section(p.section).strong) }
        }
        item(key = "scegli") {
            TextButton(onClick = { Nav.go(Screen.Catalog) }, modifier = Modifier.padding(top = 12.dp)) { Text("Scegli i giornali") }
        }
    }
}

@Composable
fun PaperRow(p: Paper, ed: Edition?, color: Color) {
    Column(Modifier.fillMaxWidth().clickable {
        if (ed != null) Nav.go(Screen.Paper(p.id))
        else Repo.update(listOf(p)) { if (Repo.editions.value[p.id] != null) Nav.go(Screen.Paper(p.id)) }
    }.padding(vertical = 12.dp)) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text(p.name, fontFamily = Display, fontWeight = FontWeight.Black, fontSize = 21.sp, color = color, modifier = Modifier.weight(1f))
            Text(when {
                ed == null -> "da scaricare"
                ed.date == Store.today() -> "${ed.articles.size} articoli"
                else -> Store.dateLabel(ed.date)
            }, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        ed?.articles?.take(2)?.forEach { a ->
            Text(a.titleIt ?: a.title, Modifier.padding(top = 4.dp), fontFamily = Reading, maxLines = 2, overflow = TextOverflow.Ellipsis,
                style = MaterialTheme.typography.bodyMedium)
        }
    }
    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
}

/** A paper's edition: its articles in its order; the headphones read it aloud */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PaperScreen(id: String) {
    val paper = Repo.paper(id)
    val editions by Repo.editions.collectAsState()
    val ed = editions[id] ?: return
    val doc = remember(ed) { ReaderDoc.of(ed) }
    val tone = LocalPalette.current.section(paper.section)
    Scaffold(topBar = {
        TopAppBar(
            title = { Column { Text(paper.name, color = tone.strong, fontWeight = FontWeight.Black)
                Text(Store.dateLabel(ed.date), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) } },
            navigationIcon = { IconButton(onClick = { Nav.back() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Indietro") } },
            actions = {
                IconButton(onClick = { Ascolta.listen(doc); Nav.tab.intValue = 1; Nav.home() }) {
                    Icon(painterResource(R.drawable.ic_headphones), "Ascolta", tint = tone.strong)
                }
            },
        )
    }) { pad ->
        LazyColumn(Modifier.padding(pad), contentPadding = PaddingValues(start = 18.dp, end = 18.dp, bottom = 24.dp)) {
            itemsIndexed(ed.articles) { i, a ->
                Column(Modifier.fillMaxWidth().clickable { Nav.go(Screen.Read(doc, i)) }.padding(vertical = 12.dp)) {
                    Text(a.titleIt ?: a.title, fontFamily = Reading, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, lineHeight = 23.sp)
                    Spacer(Modifier.height(4.dp))
                    Text(a.briefIt ?: a.brief, style = MaterialTheme.typography.bodyMedium, maxLines = 2, overflow = TextOverflow.Ellipsis,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
            }
        }
    }
}

/** Giochi e libri */
@Composable
fun Svago() {
    var which by rememberSaveable { mutableStateOf(0) }
    Column {
        Choice(listOf("Giochi", "Libri"), which) { which = it }
        if (which == 0) GiochiCover() else LibriList()
    }
}

/** Settings: which papers are on the shelves; the optional Gemini key */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CatalogScreen() {
    val selected by Repo.selected.collectAsState()
    val key by Repo.geminiKey.collectAsState()
    var draft by remember { mutableStateOf(key) }
    val pal = LocalPalette.current
    val uri = LocalUriHandler.current
    Scaffold(topBar = {
        TopAppBar(title = { Text("Impostazioni") },
            navigationIcon = { IconButton(onClick = { Repo.setGeminiKey(draft); Nav.back() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Indietro") } })
    }) { pad ->
        LazyColumn(Modifier.padding(pad), contentPadding = PaddingValues(vertical = 8.dp)) {
            item(key = "llm") {
                Card(Modifier.padding(12.dp), shape = RoundedCornerShape(16.dp),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer)) {
                    Column(Modifier.padding(14.dp)) {
                        val nanoState by Llm.nanoState.collectAsState()
                        val nanoReady = nanoState.contains(" è pronto")
                        Text("Radio e argomenti", style = MaterialTheme.typography.titleMedium)
                        Text(nanoState, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        if (!nanoReady) TextButton(onClick = { Repo.scope.launch { Llm.prepare(); Notizie.refresh() } },
                            contentPadding = PaddingValues(0.dp)) { Text("Riprova") }
                        if (!nanoReady) Text("Intanto, con una chiave gratuita di Google AI Studio li scrive Gemini online (le notizie " +
                            "di oggi vanno a Google, la voce resta sul telefono); senza, li scrive EdiKOla in modo più semplice.",
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        if (!nanoReady) {
                            Spacer(Modifier.height(8.dp))
                            OutlinedTextField(draft, { draft = it }, Modifier.fillMaxWidth(), singleLine = true,
                                label = { Text("Chiave API di Gemini (facoltativa)") },
                                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password))
                            Row {
                                TextButton(onClick = { uri.openUri("https://aistudio.google.com/apikey") }) { Text("Prendi una chiave") }
                                Spacer(Modifier.weight(1f))
                                TextButton(onClick = { Repo.setGeminiKey(draft) }) { Text("Salva") }
                            }
                        }
                    }
                }
            }
            for (s in SECTIONS) {
                item(key = "h" + s.id) {
                    Kicker(s.name, pal.section(s.id).strong, Modifier.padding(start = 16.dp, top = 16.dp, bottom = 4.dp))
                }
                items(PAPERS.filter { it.section == s.id }, key = { it.id }) { p ->
                    Row(Modifier.fillMaxWidth().clickable { Repo.toggle(p.id) }.padding(horizontal = 8.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(checked = p.id in selected, onCheckedChange = { Repo.toggle(p.id) })
                        Text(p.name, Modifier.weight(1f), fontFamily = Reading)
                        if (p.lang == "en") Text("EN", style = MaterialTheme.typography.labelSmall,
                            modifier = Modifier.padding(end = 12.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}

/** What's playing, above the bottom bar: tap for the Radio tab */
@Composable
fun MiniPlayer() {
    val st by Ascolta.state.collectAsState()
    val s = st ?: return
    Surface(color = MaterialTheme.colorScheme.primaryContainer, modifier = Modifier.fillMaxWidth().clickable { Nav.tab.intValue = 1 }) {
        Row(Modifier.padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(painterResource(if (s.radio) R.drawable.ic_podcasts else R.drawable.ic_headphones), null, Modifier.size(22.dp))
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) {
                Text(s.title + if (s.voice.isNotEmpty()) " · ${s.voice}" else "", style = MaterialTheme.typography.labelMedium)
                Text(s.titles.getOrElse(s.article) { "" }, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    fontFamily = Reading, fontWeight = FontWeight.Bold)
            }
            TextButton(onClick = { Ascolta.toggle() }) { Text(if (s.playing) "Pausa" else "Riprendi") }
        }
    }
}
