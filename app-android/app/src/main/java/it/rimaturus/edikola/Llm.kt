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

    /** Is Nano on the phone? Asked at start and every time EdiKOla comes back on screen, until it is.
     *  If it can be downloaded, the system downloads it (once): the state shows how far it got. */
    suspend fun prepare() = checking.withLock {
        if (nanoOk) return@withLock
        try {
            val m = nano ?: Generation.getClient().also { nano = it }
            when (val st = m.checkStatus()) {
                FeatureStatus.AVAILABLE -> nanoOk = true
                FeatureStatus.DOWNLOADABLE, FeatureStatus.DOWNLOADING -> {
                    nanoState.value = "Android sta scaricando Gemini Nano…"
                    m.download().collect { d ->
                        when (d) {
                            is DownloadStatus.DownloadProgress ->
                                nanoState.value = "Android sta scaricando Gemini Nano: ${d.totalBytesDownloaded / 1_000_000} MB"
                            is DownloadStatus.DownloadFailed ->
                                nanoState.value = "Download di Gemini Nano non riuscito: ${d.e.message}"
                            else -> {}
                        }
                    }
                    nanoOk = m.checkStatus() == FeatureStatus.AVAILABLE
                }
                FeatureStatus.UNAVAILABLE -> nanoState.value = "Android risponde che Gemini Nano non è disponibile per le app " +
                    "su questo telefono (UNAVAILABLE). Succede anche quando AICore non ha ancora ricevuto la configurazione: " +
                    "riavvia il telefono e riprova più tardi."
                else -> nanoState.value = "Stato di Gemini Nano sconosciuto ($st)."
            }
        } catch (e: Throwable) {
            nanoState.value = "AICore ha risposto con un errore: ${e.message ?: e.javaClass.simpleName}"
        }
        if (nanoOk) nanoState.value = "Gemini Nano è pronto: radio e argomenti si scrivono sul telefono, anche offline."
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
