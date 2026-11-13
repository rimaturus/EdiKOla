// The home screen: Edicola (the shelves), Sommario (today's news by topic, and the podcast), Giochi, Libri; the
// papers' pages, the settings, and the bar of what's being read aloud.
package it.rimaturus.edikola

import androidx.compose.foundation.BorderStroke
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
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
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
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

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
                            Text(listOf("EdiKOla", "Sommario", "La Settimana", "I miei libri")[tab],
                                style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Black)
                            Text(Store.dateLabel().replaceFirstChar { it.uppercase() }, style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    },
                    actions = {
                        if (tab <= 1) {
                            IconButton(onClick = { Repo.update(PAPERS.filter { it.id in Repo.selected.value }) },
                                enabled = progress == null) { Icon(Icons.Default.Refresh, "Aggiorna") }
                            IconButton(onClick = { Nav.go(Screen.Catalog) }) { Icon(Icons.Default.Settings, "Giornali") }
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
                MiniPlayer()
                NavigationBar {
                    val items = listOf("Edicola" to R.drawable.ic_newspaper, "Sommario" to R.drawable.ic_podcasts,
                        "Giochi" to R.drawable.ic_extension, "Libri" to R.drawable.ic_menu_book)
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
                0 -> Edicola()
                1 -> Sommario()
                2 -> GiochiCover()
                else -> LibriList()
            }
        }
    }
}

/** A row of pills, the selected one filled with its color */
@Composable
fun Pills(labels: List<String>, colors: List<Tone>, selected: Int, onSelect: (Int) -> Unit) {
    LazyRow(contentPadding = PaddingValues(vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        items(labels.size) { i ->
            val t = colors[i]
            val on = i == selected
            Surface(onClick = { onSelect(i) }, shape = CircleShape, color = if (on) t.strong else t.tint,
                contentColor = if (on) t.onStrong else t.strong) {
                Text(labels[i], Modifier.padding(horizontal = 16.dp, vertical = 8.dp), fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

@Composable
fun Edicola() {
    var section by rememberSaveable { mutableIntStateOf(0) }
    val selected by Repo.selected.collectAsState()
    val editions by Repo.editions.collectAsState()
    val pal = LocalPalette.current
    val sec = SECTIONS[section]
    val papers = PAPERS.filter { it.section == sec.id && it.id in selected }
    // the top story: the first paper of the shelf with today's edition and a photo
    val hero = papers.firstNotNullOfOrNull { p ->
        editions[p.id]?.takeIf { it.date == Store.today() && it.cover != null }?.let { p to it }
    }
    LazyVerticalGrid(GridCells.Adaptive(165.dp), contentPadding = PaddingValues(start = 12.dp, end = 12.dp, bottom = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item(span = { GridItemSpan(maxLineSpan) }) {
            Pills(SECTIONS.map { it.name }, SECTIONS.map { pal.section(it.id) }, section) { section = it }
        }
        if (hero != null) item(span = { GridItemSpan(maxLineSpan) }) { Hero(hero.first, hero.second) }
        if (papers.isEmpty()) item(span = { GridItemSpan(maxLineSpan) }) {
            Text("Nessun giornale su questo scaffale.\nTocca l'ingranaggio in alto per sceglierli.", Modifier.padding(24.dp))
        }
        items(papers, key = { it.id }) { p -> FrontPage(p, editions[p.id]) }
    }
}

/** The top story, big: photo, the paper, the headline */
@Composable
fun Hero(paper: Paper, ed: Edition) {
    val tone = LocalPalette.current.section(paper.section)
    Card(Modifier.fillMaxWidth().clickable { Nav.go(Screen.Read(ReaderDoc.of(ed), 0)) }, shape = RoundedCornerShape(20.dp)) {
        Box(Modifier.fillMaxWidth().aspectRatio(1.5f)) {
            AsyncImage(ed.cover, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
            Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.35f to Color.Transparent, 1f to Color(0xE6000000))))
            Column(Modifier.align(Alignment.BottomStart).padding(16.dp)) {
                Surface(shape = RoundedCornerShape(6.dp), color = tone.strong, contentColor = tone.onStrong) {
                    Text("IN PRIMO PIANO · ${paper.name.uppercase()}", Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
                        style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold)
                }
                Spacer(Modifier.height(8.dp))
                Text(ed.headline, color = Color.White, style = MaterialTheme.typography.headlineSmall, maxLines = 4,
                    overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

@Composable
fun FrontPage(paper: Paper, edition: Edition?) {
    val tone = LocalPalette.current.section(paper.section)
    val reading by Ascolta.state.collectAsState()
    val today = edition?.date == Store.today()
    Card(
        Modifier.fillMaxWidth().clickable {
            if (edition != null) Nav.go(Screen.Paper(paper.id))
            else Repo.update(listOf(paper)) { if (Repo.editions.value[paper.id] != null) Nav.go(Screen.Paper(paper.id)) }
        },
        shape = RoundedCornerShape(18.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer),
    ) {
        val cover = edition?.cover
        if (cover != null) {
            AsyncImage(cover, null, Modifier.fillMaxWidth().aspectRatio(1.6f), contentScale = ContentScale.Crop)
        } else {
            Box(Modifier.fillMaxWidth().aspectRatio(1.6f).background(tone.tint), contentAlignment = Alignment.Center) {
                Text(paper.name, Modifier.padding(10.dp), color = tone.strong, style = MaterialTheme.typography.titleLarge,
                    maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
        }
        Box(Modifier.fillMaxWidth().height(4.dp).background(tone.strong))
        Column(Modifier.padding(start = 12.dp, end = 12.dp, top = 10.dp, bottom = 6.dp)) {
            Text(paper.name, color = tone.strong, fontFamily = Display, fontWeight = FontWeight.Black, fontSize = 17.sp,
                maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(
                when {
                    edition == null -> "Tocca per scaricare"
                    today -> "Oggi"
                    else -> "Edizione di " + Store.dateLabel(edition.date)
                },
                style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (edition != null) {
                Spacer(Modifier.height(6.dp))
                Text(edition.headline, fontFamily = Reading, fontWeight = FontWeight.SemiBold, fontSize = 14.sp,
                    lineHeight = 18.sp, maxLines = 4, overflow = TextOverflow.Ellipsis)
                val playing = reading != null && Ascolta.isReading(edition)
                TextButton(onClick = { Ascolta.listen(edition); Nav.go(Screen.Player) }, contentPadding = PaddingValues(0.dp)) {
                    Icon(painterResource(R.drawable.ic_headphones), null, Modifier.size(18.dp), tint = tone.strong)
                    Spacer(Modifier.width(6.dp))
                    Text(if (playing) "In ascolto" else "Ascolta", color = tone.strong, fontWeight = FontWeight.SemiBold)
                }
            } else Spacer(Modifier.height(6.dp))
        }
    }
}

/** A paper's edition: the first article big, then the others */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PaperScreen(id: String) {
    val paper = Repo.paper(id)
    val editions by Repo.editions.collectAsState()
    val ed = editions[id] ?: return
    val tone = LocalPalette.current.section(paper.section)
    Scaffold(topBar = {
        TopAppBar(
            title = { Column { Text(paper.name, color = tone.strong, fontWeight = FontWeight.Black)
                Text(Store.dateLabel(ed.date), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) } },
            navigationIcon = { IconButton(onClick = { Nav.back() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Indietro") } },
            actions = {
                IconButton(onClick = { Ascolta.listen(ed); Nav.go(Screen.Player) }) {
                    Icon(painterResource(R.drawable.ic_headphones), "Ascolta", tint = tone.strong)
                }
            },
        )
    }) { pad ->
        LazyColumn(Modifier.padding(pad), contentPadding = PaddingValues(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            items(ed.articles.size) { i ->
                val a = ed.articles[i]
                val img = a.blocks.firstOrNull { it.kind == "img" }?.let { File(ed.dir, it.text) }
                if (i == 0 && img != null) Hero(paper, ed)
                else ArticleCard(a.title, a.brief, tone.strong, img) { Nav.go(Screen.Read(ReaderDoc.of(ed), i)) }
            }
        }
    }
}

@Composable
fun ArticleCard(title: String, text: String, stripe: Color, image: File?, kicker: String? = null, onClick: () -> Unit) {
    Card(Modifier.fillMaxWidth().clickable(onClick = onClick), shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer)) {
        Row(Modifier.padding(12.dp)) {
            Column(Modifier.weight(1f)) {
                if (kicker != null) Text(kicker.uppercase(), color = stripe, style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.Bold, maxLines = 1)
                Text(title, fontFamily = Reading, fontWeight = FontWeight.Bold, fontSize = 17.sp, lineHeight = 22.sp)
                if (text.isNotEmpty()) {
                    Spacer(Modifier.height(4.dp))
                    Text(text, style = MaterialTheme.typography.bodyMedium, maxLines = 3, overflow = TextOverflow.Ellipsis,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            if (image != null) {
                Spacer(Modifier.width(12.dp))
                AsyncImage(image, null, Modifier.size(92.dp).clip(RoundedCornerShape(12.dp)), contentScale = ContentScale.Crop)
            }
        }
    }
}

/** Today's news of every paper on the shelves, by topic; English ones in Italian. On top: the podcast. */
@Composable
fun Sommario() {
    val editions by Repo.editions.collectAsState()
    val pal = LocalPalette.current
    val today = remember(editions) { Repo.todays() }
    var podcast by remember { mutableStateOf(false) }
    val list = rememberLazyListState()
    val scope = rememberCoroutineScope()
    if (today.isEmpty()) {
        Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
            Text("Ancora nessuna notizia di oggi.\nTocca Aggiorna in alto.")
        }
        return
    }
    data class Row3(val paper: Paper, val ed: Edition, val i: Int, val title: String, val brief: String, val img: File?)
    val byTopic = remember(today) {
        today.flatMap { (p, ed) ->
            ed.articles.mapIndexed { i, a ->
                Row3(p, ed, i, a.titleIt ?: a.title, a.briefIt ?: a.brief, a.blocks.firstOrNull { it.kind == "img" }?.let { File(ed.dir, it.text) })
            }
        }.groupBy { Topics.of(it.title, it.brief) }
    }
    val topics = Topics.names.filter { it in byTopic }
    // where each topic's header is in the list: 0 is the podcast card, 1 the chips
    val headerIndex = remember(byTopic) {
        var k = 2
        topics.associateWith { t -> k.also { k += 1 + byTopic.getValue(t).size } }
    }
    LazyColumn(state = list, contentPadding = PaddingValues(start = 12.dp, end = 12.dp, bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        item(key = "podcast") { PodcastCard { podcast = true } }
        item(key = "chips") {
            LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                items(topics) { t ->
                    FilterChip(selected = false, onClick = { scope.launch { list.animateScrollToItem(headerIndex.getValue(t)) } },
                        label = { Text("$t · ${byTopic.getValue(t).size}") },
                        border = BorderStroke(1.dp, pal.topic(t)))
                }
            }
        }
        for (topic in topics) {
            val rows = byTopic.getValue(topic)
            item(key = topic) {
                Row(Modifier.padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(10.dp).background(pal.topic(topic), CircleShape))
                    Spacer(Modifier.width(8.dp))
                    Text(topic, style = MaterialTheme.typography.titleLarge, color = pal.topic(topic))
                    Spacer(Modifier.width(8.dp))
                    Text("${rows.size}", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            items(rows) { r ->
                ArticleCard(r.title, r.brief, pal.topic(topic), r.img, r.paper.name) { Nav.go(Screen.Read(ReaderDoc.of(r.ed), r.i)) }
            }
        }
    }
    if (podcast) PodcastDialog { podcast = false }
}

@Composable
fun PodcastCard(onClick: () -> Unit) {
    val ink = LocalPalette.current.ink
    Card(Modifier.fillMaxWidth().padding(top = 4.dp).clickable(onClick = onClick), shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(containerColor = ink.strong, contentColor = ink.onStrong)) {
        Row(Modifier.padding(18.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(56.dp).background(ink.onStrong.copy(alpha = 0.15f), CircleShape), contentAlignment = Alignment.Center) {
                Icon(painterResource(R.drawable.ic_podcasts), null, Modifier.size(30.dp))
            }
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f)) {
                Text("Il podcast di oggi", style = MaterialTheme.typography.titleLarge)
                Text("Giulia e Marco ti raccontano le notizie del giorno, nel tempo che hai.",
                    style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
}

/** How long, then the podcast is written and starts */
@Composable
fun PodcastDialog(close: () -> Unit) {
    val key by Repo.geminiKey.collectAsState()
    var minutes by rememberSaveable { mutableIntStateOf(10) }
    var busy by remember { mutableStateOf(false) }
    var note by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    AlertDialog(
        onDismissRequest = { if (!busy) close() },
        icon = { Icon(painterResource(R.drawable.ic_podcasts), null) },
        title = { Text("Il podcast di oggi") },
        text = {
            Column {
                Text("Quanto deve durare?")
                Spacer(Modifier.height(10.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    for (m in listOf(5, 10, 15, 20, 30)) {
                        FilterChip(selected = minutes == m, onClick = { minutes = m }, enabled = !busy, modifier = Modifier.weight(1f),
                            label = { Text("$m", Modifier.fillMaxWidth(), maxLines = 1, textAlign = androidx.compose.ui.text.style.TextAlign.Center) })
                    }
                }
                Text("minuti", Modifier.fillMaxWidth().padding(top = 2.dp), style = MaterialTheme.typography.labelSmall,
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(12.dp))
                Text(if (key.isNotEmpty()) "Lo scrive Gemini (online, con la tua chiave gratuita) dalle notizie di oggi; " +
                        "la voce poi è tutta sul telefono."
                    else "Lo scrive EdiKOla dalle notizie di oggi. Con una chiave gratuita di Gemini (ingranaggio in alto) " +
                        "diventa una vera conversazione.", style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (busy) Row(Modifier.padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                    Spacer(Modifier.width(10.dp))
                    Text("Scrivo la puntata…")
                }
                note?.let { Text(it, Modifier.padding(top = 8.dp), color = MaterialTheme.colorScheme.error) }
            }
        },
        confirmButton = {
            Button(enabled = !busy, onClick = {
                busy = true
                scope.launch {
                    var why: String? = null
                    val script = withContext(Dispatchers.IO) {
                        val stories = Podcast.stories()
                        var s: Podcast.Script? = null
                        if (key.isNotEmpty()) {
                            val r = Podcast.gemini(key, stories, minutes)
                            s = r.first
                            why = r.second
                        }
                        s ?: Podcast.offline(stories, minutes)
                    }
                    busy = false
                    if (script.lines.size < 3) { note = "Nessuna notizia di oggi da raccontare."; return@launch }
                    if (why != null) Repo.message.value = "Gemini: $why. Ho scritto io la puntata."
                    Ascolta.play(script)
                    close()
                    Nav.go(Screen.Player)
                }
            }) { Text("Crea e ascolta") }
        },
        dismissButton = { TextButton(onClick = close, enabled = !busy) { Text("Annulla") } },
    )
}

/** Settings: the Gemini key for the podcast, and which papers are on the shelves */
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
            item(key = "gemini") {
                Card(Modifier.padding(12.dp), shape = RoundedCornerShape(16.dp),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer)) {
                    Column(Modifier.padding(14.dp)) {
                        Text("Podcast con Gemini (facoltativo)", style = MaterialTheme.typography.titleMedium)
                        Text("Con una chiave gratuita di Google AI Studio il podcast diventa una conversazione scritta da Gemini. " +
                            "Le notizie di oggi vengono inviate a Google; la voce resta sul telefono.",
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Spacer(Modifier.height(8.dp))
                        OutlinedTextField(draft, { draft = it }, Modifier.fillMaxWidth(), singleLine = true,
                            label = { Text("Chiave API di Gemini") },
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password))
                        Row {
                            TextButton(onClick = { uri.openUri("https://aistudio.google.com/apikey") }) { Text("Prendi una chiave") }
                            Spacer(Modifier.weight(1f))
                            TextButton(onClick = { Repo.setGeminiKey(draft) }) { Text("Salva") }
                        }
                    }
                }
            }
            for (s in SECTIONS) {
                item(key = "h" + s.id) {
                    Text(s.name, Modifier.padding(start = 16.dp, top = 16.dp, bottom = 4.dp),
                        color = pal.section(s.id).strong, style = MaterialTheme.typography.titleLarge)
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
                item(key = "d" + s.id) { HorizontalDivider(Modifier.padding(top = 8.dp)) }
            }
        }
    }
}

/** What's being read aloud, above the bottom bar: tap for the player */
@Composable
fun MiniPlayer() {
    val st by Ascolta.state.collectAsState()
    val s = st ?: return
    Surface(color = MaterialTheme.colorScheme.primaryContainer, modifier = Modifier.fillMaxWidth().clickable { Nav.go(Screen.Player) }) {
        Row(Modifier.padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(painterResource(if (s.podcast) R.drawable.ic_podcasts else R.drawable.ic_headphones), null, Modifier.size(22.dp))
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
