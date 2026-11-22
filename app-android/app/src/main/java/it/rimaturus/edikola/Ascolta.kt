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
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/** The voices: one engine per language, made on first use */
object Voce {
    // it: Paola, en: Alba (British), it2: Riccardo, the second host of the podcast
    private val VOICES = mapOf("it" to "it_IT-paola-medium.onnx", "en" to "en_GB-alba-medium.onnx", "it2" to "it_IT-riccardo-x_low.onnx")
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
        val tmp = File(file.path + ".tmp")
        if (chunk.sound != null) {
            Testo.writeWav(tmp, Testo.jingle(chunk.sound), Testo.RATE, chunk.pause)
        } else {
            // the Italian voices say English words the Italian way ("Nature": nèiciur, not natùre)
            val text = if (chunk.lang.startsWith("it")) Pronuncia.italiano(chunk.text) else chunk.text
            val audio = engine(ctx, chunk.lang).generate(text)
            Testo.writeWav(tmp, audio.samples, audio.sampleRate, chunk.pause)
        }
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
        val title: String,         // "Notizie di oggi", a paper, "Radio EdiKOla"
        val titles: List<String>,  // articles, or the radio's sections
        val article: Int,
        val playing: Boolean,
        val waiting: Boolean,      // the voice (or the radio's authors) haven't made the next piece yet
        val voice: String,         // who is speaking: "Voce italiana", "Giulia"…
        val line: String,          // what is being said (shown by the radio)
        val radio: Boolean,
    )

    val state = MutableStateFlow<State?>(null)
    private var controller: MediaController? = null
    private val chunks = mutableListOf<Testo.Chunk>() // touched on the main thread only
    private val titles = mutableListOf<String>()
    private var name = ""
    private var voices: Map<String, String> = emptyMap()
    private var radio = false
    private var more = false // the radio is still being written: more pieces will come
    private var key = "" // what is being read
    private var job: Job? = null
    private var made = 0 // pieces in the playlist
    private val dir get() = File(Repo.app.cacheDir, "ascolta")
    private val NEWS_VOICES = mapOf("it" to "Voce italiana", "en" to "Voce inglese")

    fun isReading(doc: ReaderDoc) = state.value != null && key == doc.key

    /** Reads a document aloud (today's news, a paper) from section `from`; if it's already being read, jumps there */
    fun listen(doc: ReaderDoc, from: Int = 0) {
        if (!isReading(doc)) {
            val date = doc.edition?.date ?: Store.today()
            load(doc.key, doc.title, doc.sections.map { it.title },
                Testo.chunks(doc.sections.map { s -> s.title to s.blocks.filter { it.kind != "img" }.map { it.text } },
                    "${doc.title}. ${Store.dateLabel(date)}."),
                NEWS_VOICES, false, false)
        }
        withController { go(from) }
    }

    /** The radio: starts with nothing, its sections come with add() while they are written, then done() */
    fun startRadio(title: String) {
        load("radio" + System.currentTimeMillis(), title, emptyList(), emptyList(), Radio.VOICE_NAMES, true, true)
    }

    fun add(section: String, pieces: List<Testo.Chunk>) {
        if (!radio || !more) return
        val n = titles.size
        titles += section
        chunks += pieces.map { it.copy(article = n) }
        if (job?.isActive != true) withController { go(n) } else publish()
    }

    fun done() { more = false; publish() }

    private fun load(k: String, n: String, t: List<String>, c: List<Testo.Chunk>, v: Map<String, String>, r: Boolean, m: Boolean) {
        stop()
        key = k; name = n; voices = v; radio = r; more = m
        titles.addAll(t); chunks.addAll(c)
        dir.deleteRecursively()
        dir.mkdirs()
        publish()
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
            .setMediaMetadata(MediaMetadata.Builder().setTitle(titles.getOrElse(c.article) { name }).setArtist(name).build())
            .build()
    }

    /** Starts reading at section n: the playlist starts over from its first piece */
    fun go(n: Int) {
        val c = controller ?: return
        if (titles.isEmpty()) return
        val first = chunks.indexOfFirst { it.article == n.coerceIn(0, titles.size - 1) }.coerceAtLeast(0)
        job?.cancel()
        c.clearMediaItems()
        made = 0
        val ctx = Repo.app
        job = Repo.scope.launch {
            var k = first
            while (isActive) {
                if (k >= chunks.size) {
                    if (!more) break
                    delay(300) // the radio's next section is being written
                    continue
                }
                val f = File(dir, "$k.wav")
                val chunk = chunks[k]
                if (!f.exists()) try {
                    withContext(Dispatchers.Default) { Voce.synth(ctx, chunk, f) }
                } catch (e: java.io.IOException) {
                    return@launch // stopped while the voice was speaking: its folder is gone
                }
                if (!isActive) return@launch
                c.addMediaItem(item(k))
                made++
                if (made == 1) { c.prepare(); c.play() }
                else if (c.playbackState == Player.STATE_ENDED && c.playWhenReady) { // it caught up with the voice
                    c.seekTo(c.mediaItemCount - 1, 0)
                    c.play()
                }
                k++
                publish()
            }
            publish()
        }
        publish()
    }

    private fun current(): Int = controller?.currentMediaItem?.mediaId?.toIntOrNull() ?: 0

    private fun publish() {
        if (key.isEmpty()) { state.value = null; return }
        val c = controller
        val k = current().coerceIn(0, (chunks.size - 1).coerceAtLeast(0))
        val chunk = chunks.getOrNull(k)
        val working = job?.isActive == true
        state.value = State(
            title = name, titles = titles.toList(), article = chunk?.article ?: 0,
            playing = c == null || c.playWhenReady || made == 0, // before the first piece it's about to play, not paused
            waiting = c == null || made == 0 || (c.playbackState == Player.STATE_ENDED && working) ||
                c.playbackState == Player.STATE_BUFFERING,
            voice = if (chunk?.sound != null) "Sigla" else chunk?.lang?.let { voices[it] } ?: "",
            line = if (radio && chunk?.sound == null) chunk?.text.orEmpty() else "",
            radio = radio,
        )
        if (c != null && c.playbackState == Player.STATE_ENDED && !working && !more && made > 0 && k == chunks.size - 1) stop() // the end
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
        chunks.clear()
        titles.clear()
        more = false
        key = ""
        made = 0
        state.value = null
        dir.deleteRecursively()
    }
}
