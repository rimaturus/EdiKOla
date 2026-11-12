// The player screen of Ascolta: the article being read, pause, previous and next article, the list to jump to.
package it.rimaturus.edikola

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlayerScreen() {
    val st by Ascolta.state.collectAsState()
    Scaffold(topBar = {
        TopAppBar(title = { Text("Ascolta · " + (st?.paper ?: ""), fontFamily = FontFamily.Serif, fontWeight = FontWeight.Bold) },
            navigationIcon = { IconButton(onClick = { Nav.back() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Indietro") } })
    }) { pad ->
        val s = st
        if (s == null) {
            Column(Modifier.padding(pad).padding(24.dp)) {
                Text("Nessuna lettura in corso.\nTocca Ascolta su un giornale per farlo leggere ad alta voce.")
            }
            return@Scaffold
        }
        Column(Modifier.padding(pad).padding(14.dp)) {
            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer), modifier = Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp)) {
                    val what = when {
                        !s.playing -> "IN PAUSA"
                        s.waiting -> "PREPARO LA VOCE…"
                        else -> if (s.lang == "en") "VOCE INGLESE" else "VOCE ITALIANA"
                    }
                    Text("ARTICOLO ${s.article + 1} DI ${s.titles.size} · $what", style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(8.dp))
                    Text(s.titles.getOrElse(s.article) { "" }, fontFamily = FontFamily.Serif, fontWeight = FontWeight.Bold,
                        fontSize = 22.sp, lineHeight = 28.sp)
                }
            }
            Spacer(Modifier.height(12.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                FilledTonalButton(onClick = { Ascolta.go(s.article - 1) }, enabled = s.article > 0, modifier = Modifier.weight(1f)) {
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, "Articolo precedente")
                }
                Button(onClick = { Ascolta.toggle() }, modifier = Modifier.weight(2f)) {
                    Text(if (s.playing) "Pausa" else "Riprendi", fontSize = 20.sp)
                }
                FilledTonalButton(onClick = { Ascolta.go(s.article + 1) }, enabled = s.article < s.titles.size - 1,
                    modifier = Modifier.weight(1f)) { Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, "Articolo successivo") }
            }
            Text("Il volume si regola con i tasti del telefono. Continua anche a schermo spento.",
                Modifier.padding(vertical = 8.dp), style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                itemsIndexed(s.titles) { i, t ->
                    Card(Modifier.fillMaxWidth().clickable { Ascolta.go(i) }, colors = CardDefaults.cardColors(
                        containerColor = if (i == s.article) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceContainer)) {
                        Text("${i + 1}. $t", Modifier.padding(12.dp), fontFamily = FontFamily.Serif,
                            fontWeight = if (i == s.article) FontWeight.Bold else FontWeight.Normal, maxLines = 2)
                    }
                }
            }
            OutlinedButton(onClick = { Ascolta.stop(); Nav.back() }, modifier = Modifier.fillMaxWidth()) { Text("Stop") }
        }
    }
}
