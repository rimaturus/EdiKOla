// The player screen of Ascolta and of the podcast: who is speaking, the article (or topic), pause, previous and
// next, the list to jump to.
package it.rimaturus.edikola

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Three bars that move while the voice speaks */
@Composable
private fun Bars(on: Boolean, color: Color) {
    val t = rememberInfiniteTransition(label = "bars")
    Row(horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.Bottom, modifier = Modifier.height(18.dp)) {
        for (i in 0..2) {
            val h by t.animateFloat(0.3f, 1f, infiniteRepeatable(tween(420 + i * 130), RepeatMode.Reverse), label = "bar$i")
            Box(Modifier.width(4.dp).height((18 * (if (on) h else 0.3f)).dp).background(color, RoundedCornerShape(2.dp)))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlayerScreen() {
    val st by Ascolta.state.collectAsState()
    val pal = LocalPalette.current
    val ink = pal.ink
    Scaffold(topBar = {
        TopAppBar(title = { Text(st?.title ?: "Ascolta") },
            navigationIcon = { IconButton(onClick = { Nav.back() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Indietro") } })
    }) { pad ->
        val s = st
        if (s == null) {
            Column(Modifier.padding(pad).padding(24.dp)) {
                Text("Nessuna lettura in corso.\nTocca Ascolta su un giornale, o crea il podcast di oggi dal Sommario.")
            }
            return@Scaffold
        }
        val unit = if (s.podcast) "Argomento" else "Articolo"
        Column(Modifier.padding(pad).padding(horizontal = 16.dp)) {
            Card(shape = RoundedCornerShape(24.dp), modifier = Modifier.fillMaxWidth(),
                colors = CardDefaults.cardColors(containerColor = ink.strong, contentColor = ink.onStrong)) {
                Box(Modifier.background(Brush.linearGradient(listOf(ink.strong, pal.mondo.strong.copy(alpha = 0.6f))))) {
                    Column(Modifier.padding(20.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Box(Modifier.size(44.dp).background(ink.onStrong.copy(alpha = 0.15f), CircleShape), contentAlignment = Alignment.Center) {
                                Icon(painterResource(if (s.podcast) R.drawable.ic_podcasts else R.drawable.ic_headphones), null)
                            }
                            Spacer(Modifier.width(12.dp))
                            Column(Modifier.weight(1f)) {
                                Text(when {
                                    !s.playing -> "In pausa"
                                    s.waiting -> "Preparo la voce…"
                                    s.podcast -> "Parla ${s.voice}"
                                    else -> s.voice
                                }, fontWeight = FontWeight.Bold)
                                Text("$unit ${s.article + 1} di ${s.titles.size}", style = MaterialTheme.typography.labelMedium)
                            }
                            Bars(s.playing && !s.waiting, ink.onStrong)
                        }
                        Spacer(Modifier.height(18.dp))
                        Text(s.titles.getOrElse(s.article) { "" }, style = MaterialTheme.typography.headlineSmall,
                            maxLines = 4, overflow = TextOverflow.Ellipsis)
                        Spacer(Modifier.height(16.dp))
                        LinearProgressIndicator(progress = { (s.article + 1f) / s.titles.size.coerceAtLeast(1) },
                            modifier = Modifier.fillMaxWidth(), color = ink.onStrong, trackColor = ink.onStrong.copy(alpha = 0.25f))
                    }
                }
            }
            Spacer(Modifier.height(16.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly, verticalAlignment = Alignment.CenterVertically) {
                FilledTonalIconButton(onClick = { Ascolta.go(s.article - 1) }, enabled = s.article > 0, modifier = Modifier.size(56.dp)) {
                    Icon(painterResource(R.drawable.ic_skip_previous), "$unit precedente")
                }
                FilledIconButton(onClick = { Ascolta.toggle() }, modifier = Modifier.size(76.dp),
                    colors = IconButtonDefaults.filledIconButtonColors(containerColor = ink.strong, contentColor = ink.onStrong)) {
                    Icon(painterResource(if (s.playing) R.drawable.ic_pause else R.drawable.ic_play_arrow),
                        if (s.playing) "Pausa" else "Riprendi", Modifier.size(38.dp))
                }
                FilledTonalIconButton(onClick = { Ascolta.go(s.article + 1) }, enabled = s.article < s.titles.size - 1,
                    modifier = Modifier.size(56.dp)) { Icon(painterResource(R.drawable.ic_skip_next), "$unit successivo") }
            }
            Text("Il volume si regola con i tasti del telefono. Continua anche a schermo spento.",
                Modifier.fillMaxWidth().padding(vertical = 10.dp), style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                itemsIndexed(s.titles) { i, t ->
                    val now = i == s.article
                    Row(Modifier.fillMaxWidth().background(
                        if (now) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceContainer,
                        RoundedCornerShape(14.dp)).clickable { Ascolta.go(i) }.padding(12.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Text("${i + 1}", Modifier.width(30.dp), fontFamily = Display, fontWeight = FontWeight.Black, fontSize = 18.sp,
                            color = if (now) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(t, Modifier.weight(1f), fontFamily = Reading,
                            fontWeight = if (now) FontWeight.Bold else FontWeight.Normal, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
            OutlinedButton(onClick = { Ascolta.stop(); Nav.back() }, modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
                Icon(painterResource(R.drawable.ic_stop), null, Modifier.size(18.dp))
                Spacer(Modifier.width(6.dp))
                Text("Stop")
            }
        }
    }
}
