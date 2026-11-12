// The home screen: Edicola (the shelves), Sommario (today's news by topic), Giochi, Libri; the papers' pages,
// the catalog, and the bar of what's being read aloud.
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
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Star
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
import androidx.compose.material3.ScrollableTabRow
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
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
                            Text(listOf("Edicola", "Sommario", "La Settimana di EdiKOla", "I miei libri")[tab],
                                fontFamily = FontFamily.Serif, fontWeight = FontWeight.Bold)
                            Text(Store.dateLabel(), style = MaterialTheme.typography.labelMedium)
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
                    val items = listOf("Edicola" to Icons.Default.Home, "Sommario" to Icons.AutoMirrored.Filled.List,
                        "Giochi" to Icons.Default.Edit, "Libri" to Icons.Default.Star)
                    items.forEachIndexed { i, (label, icon) ->
                        NavigationBarItem(selected = tab == i, onClick = { Nav.tab.intValue = i },
                            icon = { Icon(icon, label) }, label = { Text(label) })
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

@Composable
fun Edicola() {
    var section by rememberSaveable { mutableIntStateOf(0) }
    val selected by Repo.selected.collectAsState()
    val editions by Repo.editions.collectAsState()
    val pal = LocalPalette.current
    Column {
        ScrollableTabRow(selectedTabIndex = section, edgePadding = 8.dp) {
            SECTIONS.forEachIndexed { i, s ->
                val tone = pal.section(s.id)
                Tab(selected = section == i, onClick = { section = i },
                    text = { Text(s.name, color = tone.strong, fontWeight = if (section == i) FontWeight.Bold else FontWeight.Normal) })
            }
        }
        val sec = SECTIONS[section]
        val papers = PAPERS.filter { it.section == sec.id && it.id in selected }
        if (papers.isEmpty()) {
            Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
                Text("Nessun giornale su questo scaffale.\nTocca l'ingranaggio in alto per sceglierli.")
            }
            return
        }
        LazyVerticalGrid(GridCells.Adaptive(160.dp), contentPadding = PaddingValues(10.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            items(papers, key = { it.id }) { p -> FrontPage(p, editions[p.id]) }
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
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer),
    ) {
        Text(paper.name, Modifier.fillMaxWidth().background(tone.strong).padding(horizontal = 8.dp, vertical = 6.dp),
            color = tone.onStrong, fontFamily = FontFamily.Serif, fontWeight = FontWeight.Bold, maxLines = 1,
            overflow = TextOverflow.Ellipsis)
        Column(Modifier.padding(8.dp)) {
            Text(
                when {
                    edition == null -> "Tocca per scaricare"
                    today -> Store.dateLabel(edition.date)
                    else -> "Edizione di " + Store.dateLabel(edition.date)
                },
                style = MaterialTheme.typography.labelSmall, fontFamily = FontFamily.Serif,
            )
            if (edition != null) {
                Spacer(Modifier.height(4.dp))
                Text(edition.headline, fontFamily = FontFamily.Serif, fontWeight = FontWeight.Bold, fontSize = 14.sp,
                    lineHeight = 17.sp, maxLines = 3, overflow = TextOverflow.Ellipsis)
                edition.cover?.let {
                    Spacer(Modifier.height(6.dp))
                    AsyncImage(it, null, Modifier.fillMaxWidth().aspectRatio(1.6f).clip(RoundedCornerShape(6.dp)),
                        contentScale = ContentScale.Crop)
                }
                Spacer(Modifier.height(6.dp))
                val playing = reading != null && Ascolta.isReading(edition)
                TextButton(onClick = { Ascolta.listen(edition); Nav.go(Screen.Player) }, Modifier.fillMaxWidth(),
                    colors = androidx.compose.material3.ButtonDefaults.textButtonColors(containerColor = tone.tint, contentColor = tone.strong)) {
                    Icon(Icons.Default.PlayArrow, null, Modifier.size(18.dp))
                    Spacer(Modifier.width(4.dp))
                    Text(if (playing) "In ascolto" else "Ascolta")
                }
            }
        }
    }
}

/** A paper's edition: its articles, tap one to read it */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PaperScreen(id: String) {
    val paper = Repo.paper(id)
    val editions by Repo.editions.collectAsState()
    val ed = editions[id] ?: return
    val tone = LocalPalette.current.section(paper.section)
    Scaffold(topBar = {
        TopAppBar(
            title = { Column { Text(paper.name, fontFamily = FontFamily.Serif, fontWeight = FontWeight.Bold)
                Text(Store.dateLabel(ed.date), style = MaterialTheme.typography.labelMedium) } },
            navigationIcon = { IconButton(onClick = { Nav.back() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Indietro") } },
            actions = {
                TextButton(onClick = { Ascolta.listen(ed); Nav.go(Screen.Player) }) {
                    Icon(Icons.Default.PlayArrow, null); Text("Ascolta")
                }
            },
        )
    }) { pad ->
        LazyColumn(Modifier.padding(pad), contentPadding = PaddingValues(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            items(ed.articles.size) { i ->
                val a = ed.articles[i]
                ArticleCard(a.title, a.brief, tone.strong, a.blocks.firstOrNull { it.kind == "img" }?.let { File(ed.dir, it.text) }) {
                    Nav.go(Screen.Read(ReaderDoc.of(ed), i))
                }
            }
        }
    }
}

@Composable
fun ArticleCard(title: String, text: String, stripe: androidx.compose.ui.graphics.Color, image: File?, onClick: () -> Unit) {
    Card(Modifier.fillMaxWidth().clickable(onClick = onClick),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer)) {
        Row(Modifier.padding(10.dp)) {
            Box(Modifier.width(6.dp).height(64.dp).background(stripe, RoundedCornerShape(3.dp)))
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)) {
                Text(title, fontFamily = FontFamily.Serif, fontWeight = FontWeight.Bold, fontSize = 17.sp, lineHeight = 21.sp)
                if (text.isNotEmpty()) {
                    Spacer(Modifier.height(4.dp))
                    Text(text, style = MaterialTheme.typography.bodyMedium, maxLines = 3, overflow = TextOverflow.Ellipsis,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            if (image != null) {
                Spacer(Modifier.width(10.dp))
                AsyncImage(image, null, Modifier.size(84.dp, 64.dp).clip(RoundedCornerShape(6.dp)), contentScale = ContentScale.Crop)
            }
        }
    }
}

/** Today's news of every paper on the shelves, by topic; English ones in Italian */
@Composable
fun Sommario() {
    val editions by Repo.editions.collectAsState()
    val pal = LocalPalette.current
    val today = remember(editions) { Repo.todays() }
    if (today.isEmpty()) {
        Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
            Text("Ancora nessuna notizia di oggi.\nTocca Aggiorna in alto.")
        }
        return
    }
    data class Row3(val paper: Paper, val ed: Edition, val i: Int, val title: String, val brief: String)
    val byTopic = remember(today) {
        today.flatMap { (p, ed) -> ed.articles.mapIndexed { i, a -> Row3(p, ed, i, a.titleIt ?: a.title, a.briefIt ?: a.brief) } }
            .groupBy { Topics.of(it.title, it.brief) }
    }
    LazyColumn(contentPadding = PaddingValues(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        for (topic in Topics.names) {
            val list = byTopic[topic] ?: continue
            item(key = topic) {
                Column(Modifier.padding(top = 10.dp)) {
                    Text("${topic.uppercase()} · ${list.size}", color = pal.topic(topic), fontWeight = FontWeight.Bold,
                        style = MaterialTheme.typography.labelLarge)
                    HorizontalDivider(color = pal.topic(topic), thickness = 2.dp)
                }
            }
            items(list) { r ->
                ArticleCard(r.title, r.paper.name + " · " + r.brief, pal.topic(topic), null) {
                    Nav.go(Screen.Read(ReaderDoc.of(r.ed), r.i))
                }
            }
        }
    }
}

/** Which papers are on the shelves */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CatalogScreen() {
    val selected by Repo.selected.collectAsState()
    val pal = LocalPalette.current
    Scaffold(topBar = {
        TopAppBar(title = { Text("Scegli i giornali") },
            navigationIcon = { IconButton(onClick = { Nav.back() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Indietro") } })
    }) { pad ->
        LazyColumn(Modifier.padding(pad), contentPadding = PaddingValues(vertical = 8.dp)) {
            for (s in SECTIONS) {
                item(key = "h" + s.id) {
                    Text(s.name.uppercase(), Modifier.padding(start = 16.dp, top = 16.dp, bottom = 4.dp),
                        color = pal.section(s.id).strong, fontWeight = FontWeight.Bold)
                }
                items(PAPERS.filter { it.section == s.id }, key = { it.id }) { p ->
                    Row(Modifier.fillMaxWidth().clickable { Repo.toggle(p.id) }.padding(horizontal = 8.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(checked = p.id in selected, onCheckedChange = { Repo.toggle(p.id) })
                        Text(p.name, Modifier.weight(1f))
                        if (p.lang == "en") Text("EN", style = MaterialTheme.typography.labelSmall,
                            modifier = Modifier.padding(end = 12.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
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
        Row(Modifier.padding(horizontal = 12.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(s.paper, style = MaterialTheme.typography.labelMedium)
                Text(s.titles.getOrElse(s.article) { "" }, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    fontFamily = FontFamily.Serif, fontWeight = FontWeight.Bold)
            }
            TextButton(onClick = { Ascolta.toggle() }) { Text(if (s.playing) "Pausa" else "Riprendi") }
        }
    }
}
