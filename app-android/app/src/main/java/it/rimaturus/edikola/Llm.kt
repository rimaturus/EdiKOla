// The language model that sorts the news and writes the radio show.
// First choice: Gemini Nano, the model built into Android (AICore) on recent phones like the Galaxy S25: free,
// offline, nothing leaves the phone (ML Kit Prompt API). It only answers while EdiKOla is on screen.
// Without Nano, Gemini online with the user's free key (Google AI Studio), if there is one. Otherwise null: the
// callers fall back to what EdiKOla does by itself (keywords, the round-up written from templates).
package it.rimaturus.edikola

import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.GenerativeModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

object Llm {
    private var nano: GenerativeModel? = null
    @Volatile private var nanoOk = false

    /** At start: is Nano on the phone? If it can be downloaded, the system downloads it (once, in the background). */
    suspend fun prepare() {
        try {
            val m = nano ?: Generation.getClient().also { nano = it }
            when (m.checkStatus()) {
                FeatureStatus.AVAILABLE -> nanoOk = true
                FeatureStatus.DOWNLOADABLE -> { m.download().collect { }; nanoOk = m.checkStatus() == FeatureStatus.AVAILABLE }
                else -> {}
            }
        } catch (e: Throwable) { /* no AICore on this phone */ }
    }

    /** Who answers, for the screens: "Gemini Nano", "Gemini", or null */
    fun who(): String? = if (nanoOk) "Gemini Nano" else if (Repo.geminiKey.value.isNotEmpty()) "Gemini" else null

    /** The model's answer, or null (no model, offline, quota, EdiKOla in the background) */
    suspend fun ask(prompt: String): String? {
        if (nanoOk) try {
            val t = nano!!.generateContent(prompt).candidates.firstOrNull()?.text?.trim()
            if (!t.isNullOrEmpty()) return t
        } catch (e: Throwable) { /* busy, quota, background: try the next way */ }
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
