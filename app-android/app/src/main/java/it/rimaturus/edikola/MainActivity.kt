package it.rimaturus.edikola

import android.content.Intent
import android.media.AudioManager
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateListOf

/** Where the user is: the screens on top of the Edicola, last one showing */
sealed class Screen {
    data object Home : Screen()
    data class Paper(val id: String) : Screen()
    data class Read(val doc: ReaderDoc, val section: Int) : Screen()
    data class Pdf(val file: java.io.File) : Screen()
    data object Catalog : Screen()
    data object Player : Screen()
    data class Game(val which: String) : Screen()
}

object Nav {
    val stack = mutableStateListOf<Screen>(Screen.Home)
    /** the bottom bar's tab on the home screen */
    val tab = androidx.compose.runtime.mutableIntStateOf(0)
    fun go(s: Screen) { stack += s }
    fun back(): Boolean = if (stack.size > 1) { stack.removeAt(stack.size - 1); true } else false
}

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        volumeControlStream = AudioManager.STREAM_MUSIC // the volume keys set the voice's volume
        handle(intent)
        setContent { EdikolaTheme { Root() } }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    // A book shared or opened from another app (EPUB, PDF): into "I miei libri", then open it
    private fun handle(intent: Intent?) {
        val uri: Uri = when (intent?.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> if (android.os.Build.VERSION.SDK_INT >= 33)
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                else @Suppress("DEPRECATION") intent.getParcelableExtra(Intent.EXTRA_STREAM)
            else -> null
        } ?: return
        val f = Libri.import(this, uri) ?: return
        Nav.tab.intValue = 3
        Libri.open(f)
    }
}

@Composable
fun Root() {
    BackHandler(enabled = Nav.stack.size > 1) { Nav.back() }
    when (val s = Nav.stack.last()) {
        Screen.Home -> HomeScreen()
        is Screen.Paper -> PaperScreen(s.id)
        is Screen.Read -> ReaderScreen(s.doc, s.section)
        is Screen.Pdf -> PdfScreen(s.file)
        Screen.Catalog -> CatalogScreen()
        Screen.Player -> PlayerScreen()
        is Screen.Game -> GameScreen(s.which)
    }
}
