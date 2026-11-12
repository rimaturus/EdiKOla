// Ascolta: a newspaper read aloud like an audiobook, offline.
// sherpa-onnx makes the audio a few sentences ahead (Piper voices: Paola for Italian, Alba for English, chosen
// per article), media3's ExoPlayer plays it in a media session: speaker as media audio, volume keys, the
// notification and lock screen controls, and it goes on with the screen off or in another app.
package it.rimaturus.edikola

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.ContextCompat
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaController
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import androidx.media3.session.SessionToken
import com.k2fsa.sherpa.onnx.OfflineTts
import com.k2fsa.sherpa.onnx.OfflineTtsConfig
import com.k2fsa.sherpa.onnx.OfflineTtsModelConfig
import com.k2fsa.sherpa.onnx.OfflineTtsVitsModelConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/** The voices: one engine per language, made on first use */
object Voce {
    private val VOICES = mapOf("it" to "it_IT-paola-medium.onnx", "en" to "en_GB-alba-medium.onnx")
    private val engines = mutableMapOf<String, OfflineTts>()
    private const val DATA_VERSION = "1"

    // espeak-ng (the pronunciation rules) needs real files: copied out of the APK once
    private fun dataDir(ctx: Context): String {
        val dir = File(ctx.filesDir, "espeak-ng-data")
        val mark = File(dir, ".v$DATA_VERSION")
        if (!mark.exists()) {
            dir.deleteRecursively()
            fun copy(asset: String, to: File) {
                val list = ctx.assets.list(asset) ?: emptyArray()
                if (list.isEmpty()) {
                    to.parentFile?.mkdirs()
                    ctx.assets.open(asset).use { i -> to.outputStream().use { i.copyTo(it) } }
                } else list.forEach { copy("$asset/$it", File(to, it)) }
            }
            copy("voci/espeak-ng-data", dir)
            mark.writeText("")
        }
        return dir.absolutePath
    }

    @Synchronized
    private fun engine(ctx: Context, lang: String): OfflineTts = engines.getOrPut(lang) {
        val config = OfflineTtsConfig(
            model = OfflineTtsModelConfig(
                vits = OfflineTtsVitsModelConfig(
                    model = "voci/$lang/${VOICES.getValue(lang)}",
                    tokens = "voci/$lang/tokens.txt",
                    dataDir = dataDir(ctx),
                ),
                numThreads = 4,
            ),
        )
        OfflineTts(assetManager = ctx.assets, config = config)
    }

    /** Writes the piece's audio (WAV, with its pause after it). One at a time: a jump to another article
     *  waits for the piece being made (a native call can't be stopped halfway). */
    @Synchronized
    fun synth(ctx: Context, chunk: Testo.Chunk, file: File) {
        val audio = engine(ctx, chunk.lang).generate(chunk.text)
        val tmp = File(file.path + ".tmp")
        Testo.writeWav(tmp, audio.samples, audio.sampleRate, chunk.pause)
        tmp.renameTo(file)
    }
}

class AscoltaService : MediaSessionService() {
    private var session: MediaSession? = null

    override fun onCreate() {
        super.onCreate()
        val player = ExoPlayer.Builder(this)
            .setAudioAttributes(
                AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_SPEECH).build(),
                true, // audio focus: pauses for a call, ducks for a notification
            )
            .setHandleAudioBecomingNoisy(true) // headphones unplugged: pause
            .setWakeMode(C.WAKE_MODE_LOCAL)
            .build()
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        session = MediaSession.Builder(this, player).setSessionActivity(open).build()
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = session

    override fun onTaskRemoved(rootIntent: Intent?) {
        val p = session?.player
        if (p == null || !p.playWhenReady || p.mediaItemCount == 0) stopSelf()
    }

    override fun onDestroy() {
        session?.run { player.release(); release() }
        session = null
        super.onDestroy()
    }
}

object Ascolta {
    /** What the player screen shows */
    data class State(
        val paper: String,
        val titles: List<String>,
        val article: Int,
        val playing: Boolean,
        val waiting: Boolean, // the voice hasn't made the next piece yet
        val lang: String,
    )

    val state = MutableStateFlow<State?>(null)
    private var controller: MediaController? = null
    private var chunks: List<Testo.Chunk> = emptyList()
    private var paperName = ""
    private var titles: List<String> = emptyList()
    private var key = "" // the edition being read
    private var job: Job? = null
    private var made = 0 // pieces in the playlist
    private val dir get() = File(Repo.app.cacheDir, "ascolta")

    fun isReading(edition: Edition) = state.value != null && key == edition.paper + edition.date

    /** Reads an edition aloud from article `from`. If it's the one being read: jumps there, or with no `from`
     *  just goes on (the player screen shows it). */
    fun listen(edition: Edition, from: Int? = null) {
        val p = Repo.paper(edition.paper)
        if (isReading(edition) && from == null) return
        if (!isReading(edition)) {
            stop()
            key = edition.paper + edition.date
            paperName = p.name
            titles = edition.articles.map { it.title }
            chunks = Testo.chunks(edition.articles.map { it.title to it.paragraphs },
                "${p.name}. ${Store.dateLabel(edition.date)}.")
            dir.deleteRecursively()
            dir.mkdirs()
        }
        withController { go(from ?: 0) }
    }

    private fun withController(then: () -> Unit) {
        controller?.let { return then() }
        val ctx = Repo.app
        val token = SessionToken(ctx, ComponentName(ctx, AscoltaService::class.java))
        val future = MediaController.Builder(ctx, token).buildAsync()
        future.addListener({
            val c = future.get()
            controller = c
            c.addListener(object : Player.Listener {
                override fun onEvents(player: Player, events: Player.Events) = publish()
            })
            then()
        }, ContextCompat.getMainExecutor(ctx))
    }

    private fun item(k: Int): MediaItem {
        val c = chunks[k]
        return MediaItem.Builder().setMediaId(k.toString()).setUri(Uri.fromFile(File(dir, "$k.wav")))
            .setMediaMetadata(MediaMetadata.Builder().setTitle(titles[c.article]).setArtist(paperName).build())
            .build()
    }

    /** Starts reading at article n: the playlist starts over from its first piece */
    fun go(n: Int) {
        val c = controller ?: return
        val first = chunks.indexOfFirst { it.article == n.coerceIn(0, titles.size - 1) }.coerceAtLeast(0)
        job?.cancel()
        c.clearMediaItems()
        made = 0
        val ctx = Repo.app
        job = Repo.scope.launch {
            for (k in first until chunks.size) {
                val f = File(dir, "$k.wav")
                if (!f.exists()) withContext(Dispatchers.Default) { Voce.synth(ctx, chunks[k], f) }
                if (!isActive) return@launch
                c.addMediaItem(item(k))
                made++
                if (made == 1) { c.prepare(); c.play() }
                else if (c.playbackState == Player.STATE_ENDED && c.playWhenReady) { // it caught up with the voice
                    c.seekTo(c.mediaItemCount - 1, 0)
                    c.play()
                }
                publish()
            }
        }
        publish()
    }

    private fun current(): Int {
        val c = controller ?: return 0
        return c.currentMediaItem?.mediaId?.toIntOrNull() ?: 0
    }

    private fun publish() {
        val c = controller
        if (c == null || chunks.isEmpty()) { state.value = null; return }
        val k = current().coerceIn(0, chunks.size - 1)
        state.value = State(
            paper = paperName, titles = titles, article = chunks[k].article,
            playing = c.playWhenReady || made == 0, // before the first piece it's about to play, not paused
            waiting = made == 0 || (c.playbackState == Player.STATE_ENDED && job?.isActive == true) ||
                c.playbackState == Player.STATE_BUFFERING,
            lang = chunks[k].lang,
        )
        if (c.playbackState == Player.STATE_ENDED && job?.isCompleted == true && k == chunks.size - 1) stop() // the end
    }

    fun toggle() {
        val c = controller ?: return
        if (c.playWhenReady) c.pause() else c.play()
    }

    fun stop() {
        job?.cancel()
        job = null
        controller?.run { stop(); clearMediaItems(); release() }
        controller = null
        chunks = emptyList()
        key = ""
        state.value = null
        dir.deleteRecursively()
    }
}
