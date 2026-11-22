// The Radio tab. Nothing playing: switch on Radio EdiKOla (how long), or have today's news read aloud.
// Playing: who speaks and what they say, the section, pause, previous and next, the list to jump to.
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
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

@Composable
fun RadioScreen() {
    val st by Ascolta.state.collectAsState()
    val s = st
    if (s == null) RadioStart() else Playing(s)
}

@Composable
private fun RadioStart() {
    val ink = LocalPalette.current.ink
    val stories by Notizie.oggi.collectAsState()
    var minutes by rememberSaveable { mutableIntStateOf(10) }
    Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Card(shape = RoundedCornerShape(24.dp), colors = CardDefaults.cardColors(containerColor = ink.strong, contentColor = ink.onStrong)) {
            Column(Modifier.padding(20.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(48.dp).background(ink.onStrong.copy(alpha = 0.15f), CircleShape), contentAlignment = Alignment.Center) {
                        Icon(painterResource(R.drawable.ic_podcasts), null, Modifier.size(28.dp))
                    }
                    Spacer(Modifier.width(12.dp))
                    Text(Radio.TITLE, fontFamily = Display, fontWeight = FontWeight.Black, fontSize = 28.sp)
                }
                Spacer(Modifier.height(10.dp))
                Text("Giulia e Marco ti raccontano le notizie di oggi come in radio: la sigla, la notizia d'apertura, " +
                    "un argomento dopo l'altro, domande e commenti.", style = MaterialTheme.typography.bodyLarge)
                Spacer(Modifier.height(16.dp))
                Text("Quanto dura?", fontWeight = FontWeight.Bold)
                Row(Modifier.padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    for (m in listOf(5, 10, 15, 20, 30)) {
                        FilterChip(selected = minutes == m, onClick = { minutes = m }, modifier = Modifier.weight(1f),
                            label = { Text("$m′", Modifier.fillMaxWidth(), textAlign = TextAlign.Center, maxLines = 1) },
                            colors = FilterChipDefaults.filterChipColors(labelColor = ink.onStrong,
                                selectedContainerColor = ink.onStrong, selectedLabelColor = ink.strong))
                    }
                }
                Spacer(Modifier.height(16.dp))
                Button(onClick = { Radio.start(minutes) }, enabled = stories.isNotEmpty(), modifier = Modifier.fillMaxWidth().height(52.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = ink.onStrong, contentColor = ink.strong)) {
                    Icon(painterResource(R.drawable.ic_play_arrow), null)
                    Spacer(Modifier.width(8.dp))
                    Text("Accendi la radio", fontWeight = FontWeight.Bold)
                }
                Spacer(Modifier.height(8.dp))
                Text(when (Llm.who()) {
                    "Gemini Nano" -> "La scrive Gemini Nano sul telefono, mentre ascolti. Anche le voci sono sul telefono."
                    "Gemini" -> "La scrive Gemini online con la tua chiave; le voci sono sul telefono."
                    else -> "Senza Gemini Nano la scrive EdiKOla, in modo più semplice."
                }, style = MaterialTheme.typography.bodySmall)
            }
        }
        Card(shape = RoundedCornerShape(24.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer)) {
            Column(Modifier.padding(20.dp)) {
                Text("Leggimi le notizie", style = MaterialTheme.typography.titleLarge)
                Spacer(Modifier.height(6.dp))
                Text("Gli articoli di oggi, interi, uno dopo l'altro come un audiolibro, nell'ordine di Oggi.",
                    style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(12.dp))
                OutlinedButton(onClick = { Ascolta.listen(ReaderDoc.oggi(Layout(stories).order)) }, enabled = stories.isNotEmpty()) {
                    Icon(painterResource(R.drawable.ic_headphones), null, Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text("Ascolta")
                }
            }
        }
        if (stories.isEmpty()) Text("Ancora nessuna notizia di oggi: aggiorna i giornali in Oggi.",
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun Playing(s: Ascolta.State) {
    val pal = LocalPalette.current
    val ink = pal.ink
    val writing by Radio.status.collectAsState()
    val unit = if (s.radio) "Parte" else "Articolo"
    Column(Modifier.padding(horizontal = 16.dp)) {
        Card(shape = RoundedCornerShape(24.dp), modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
            colors = CardDefaults.cardColors(containerColor = ink.strong, contentColor = ink.onStrong)) {
            Column(Modifier.padding(20.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(s.title.uppercase(), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold, letterSpacing = 1.sp)
                        Text(when {
                            !s.playing -> "In pausa"
                            s.waiting -> if (s.radio) "Un attimo…" else "Preparo la voce…"
                            s.radio && s.voice != "Sigla" -> "Parla ${s.voice}"
                            else -> s.voice
                        }, fontWeight = FontWeight.Bold, fontSize = 18.sp)
                    }
                    Bars(s.playing && !s.waiting, ink.onStrong)
                }
                Spacer(Modifier.height(14.dp))
                Text(s.titles.getOrElse(s.article) { "" }, style = MaterialTheme.typography.headlineSmall, maxLines = 3,
                    overflow = TextOverflow.Ellipsis)
                if (s.line.isNotEmpty()) {
                    Spacer(Modifier.height(10.dp))
                    Text("«${s.line}»", fontFamily = Reading, fontStyle = FontStyle.Italic, maxLines = 5, overflow = TextOverflow.Ellipsis)
                }
                Spacer(Modifier.height(14.dp))
                LinearProgressIndicator(progress = { (s.article + 1f) / s.titles.size.coerceAtLeast(1) },
                    modifier = Modifier.fillMaxWidth(), color = ink.onStrong, trackColor = ink.onStrong.copy(alpha = 0.25f))
            }
        }
        writing?.let { Text("✎ $it…", Modifier.padding(top = 8.dp), style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant) }
        Row(Modifier.fillMaxWidth().padding(vertical = 14.dp), horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.CenterVertically) {
            FilledTonalIconButton(onClick = { Ascolta.go(s.article - 1) }, enabled = s.article > 0, modifier = Modifier.size(56.dp)) {
                Icon(painterResource(R.drawable.ic_skip_previous), "$unit precedente")
            }
            FilledIconButton(onClick = { Ascolta.toggle() }, modifier = Modifier.size(76.dp),
                colors = IconButtonDefaults.filledIconButtonColors(containerColor = ink.strong, contentColor = ink.onStrong)) {
                Icon(painterResource(if (s.playing) R.drawable.ic_pause else R.drawable.ic_play_arrow),
                    if (s.playing) "Pausa" else "Riprendi", Modifier.size(38.dp))
            }
            FilledTonalIconButton(onClick = { Ascolta.go(s.article + 1) }, enabled = s.article < s.titles.size - 1,
                modifier = Modifier.size(56.dp)) { Icon(painterResource(R.drawable.ic_skip_next), "$unit successiva") }
        }
        LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(vertical = 4.dp)) {
            itemsIndexed(s.titles) { i, t ->
                val now = i == s.article
                Row(Modifier.fillMaxWidth().background(if (now) MaterialTheme.colorScheme.primaryContainer else Color.Transparent,
                    RoundedCornerShape(12.dp)).clickable { Ascolta.go(i) }.padding(horizontal = 12.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    Text("${i + 1}", Modifier.width(30.dp), fontFamily = Display, fontWeight = FontWeight.Black,
                        color = if (now) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(t, Modifier.weight(1f), fontFamily = Reading, fontWeight = if (now) FontWeight.Bold else FontWeight.Normal,
                        maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
            }
        }
        OutlinedButton(onClick = { Ascolta.stop() }, modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
            Icon(painterResource(R.drawable.ic_stop), null, Modifier.size(18.dp))
            Spacer(Modifier.width(6.dp))
            Text("Spegni")
        }
    }
}
