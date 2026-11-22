// The language model that sorts the news and writes the radio show.
// First choice: Gemini Nano, the model built into Android (AICore) on recent phones like the Galaxy S25: free,
// offline, nothing leaves the phone (ML Kit Prompt API). It only answers while EdiKOla is on screen.
// Without Nano, Gemini online with the user's free key (Google AI Studio), if there is one. Otherwise null: the
// callers fall back to what EdiKOla does by itself (keywords, the round-up written from templates).
package it.rimaturus.edikola

import com.google.mlkit.genai.common.DownloadStatus
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.GenerativeModel
import com.google.mlkit.genai.prompt.ModelPreference
import com.google.mlkit.genai.prompt.ModelReleaseStage
import com.google.mlkit.genai.prompt.generationConfig
import com.google.mlkit.genai.prompt.modelConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

object Llm {
    private var nano: GenerativeModel? = null
    @Volatile private var nanoOk = false
    private val checking = Mutex()
    /** What Android says about Nano, in words, for the settings */
    val nanoState = MutableStateFlow("Controllo Gemini Nano…")

    // The models to try: the phone's stable Nano, then the preview ones (Gemini Nano 4 / Gemma 4), which on phones
    // other than Pixel come through the AICore Developer Preview (Developer options > AICore Settings)
    private val MODELS: List<Pair<String, () -> GenerativeModel>> = listOf(
        "Gemini Nano" to { Generation.getClient() },
        "Gemini Nano in anteprima" to { Generation.getClient(generationConfig {
            modelConfig = modelConfig { releaseStage = ModelReleaseStage.PREVIEW; preference = ModelPreference.FULL } }) },
        "Gemini Nano in anteprima (veloce)" to { Generation.getClient(generationConfig {
            modelConfig = modelConfig { releaseStage = ModelReleaseStage.PREVIEW; preference = ModelPreference.FAST } }) },
    )

    /** Is Nano on the phone? Asked at start and every time EdiKOla comes back on screen, until it is.
     *  If it can be downloaded, the system downloads it (once): the state shows how far it got. */
    suspend fun prepare() = checking.withLock {
        if (nanoOk) return@withLock
        val errors = mutableListOf<String>()
        for ((name, make) in MODELS) {
            try {
                val m = make()
                when (m.checkStatus()) {
                    FeatureStatus.AVAILABLE -> { nano = m; nanoOk = true }
                    FeatureStatus.DOWNLOADABLE, FeatureStatus.DOWNLOADING -> {
                        nanoState.value = "Android sta scaricando $name…"
                        m.download().collect { d ->
                            when (d) {
                                is DownloadStatus.DownloadProgress ->
                                    nanoState.value = "Android sta scaricando $name: ${d.totalBytesDownloaded / 1_000_000} MB"
                                is DownloadStatus.DownloadFailed -> errors += "download di $name non riuscito: ${d.e.message}"
                                else -> {}
                            }
                        }
                        if (m.checkStatus() == FeatureStatus.AVAILABLE) { nano = m; nanoOk = true }
                    }
                    else -> errors += "$name: non disponibile"
                }
                if (nanoOk) { nanoState.value = "$name è pronto: radio e argomenti si scrivono sul telefono, anche offline."; break }
                m.close()
            } catch (e: Throwable) {
                errors += "$name: ${e.message ?: e.javaClass.simpleName}"
            }
        }
        if (!nanoOk) nanoState.value = "Android risponde che Gemini Nano non è disponibile per le app (" + errors.joinToString("; ") +
            "). Sui Samsung il modello nuovo passa dall'anteprima di AICore: Opzioni sviluppatore > AICore Settings > " +
            "Enable AICore Developer Preview, poi nell'app AICore, scheda Test, scegli un modello Preview e scaricalo; " +
            "infine tocca Riprova."
    }

    /** Who answers, for the screens: "Gemini Nano", "Gemini", or null */
    fun who(): String? = if (nanoOk) "Gemini Nano" else if (Repo.geminiKey.value.isNotEmpty()) "Gemini" else null

    /** The model's answer, or null (no model, offline, quota, EdiKOla in the background) */
    suspend fun ask(prompt: String): String? {
        if (nanoOk) try {
            val t = nano!!.generateContent(prompt).candidates.firstOrNull()?.text?.trim()
            if (!t.isNullOrEmpty()) return t
        } catch (e: Throwable) {
            nanoState.value = "Gemini Nano è pronto, ma l'ultima risposta non è riuscita: ${e.message ?: e.javaClass.simpleName}"
        }
        val key = Repo.geminiKey.value
        return if (key.isNotEmpty()) withContext(Dispatchers.IO) { online(key, prompt) } else null
    }

    private fun online(key: String, prompt: String): String? {
        val body = JSONObject().put("contents", JSONArray().put(JSONObject().put("role", "user")
            .put("parts", JSONArray().put(JSONObject().put("text", prompt))))).toString()
        for (model in listOf("gemini-flash-lite-latest", "gemini-flash-latest")) {
            val c = URL("https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent").openConnection() as HttpURLConnection
            try {
                c.requestMethod = "POST"
                c.doOutput = true
                c.connectTimeout = 15000
                c.readTimeout = 90000
                c.setRequestProperty("Content-Type", "application/json")
                c.setRequestProperty("x-goog-api-key", key)
                c.outputStream.use { it.write(body.toByteArray()) }
                when (c.responseCode) {
                    200 -> {
                        val parts = JSONObject(c.inputStream.use { String(it.readBytes()) }).getJSONArray("candidates")
                            .getJSONObject(0).getJSONObject("content").getJSONArray("parts")
                        return (0 until parts.length()).map { parts.getJSONObject(it) }.filter { !it.optBoolean("thought") }
                            .joinToString("") { it.optString("text") }.trim().ifEmpty { null }
                    }
                    400, 401, 403 -> return null // the key is wrong
                }
            } catch (e: Exception) {
                return null // offline
            } finally {
                c.disconnect()
            }
        }
        return null
    }
}
