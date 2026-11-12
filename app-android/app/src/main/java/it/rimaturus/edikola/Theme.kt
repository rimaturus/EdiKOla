// Colors: EdiKOla's palette in a light and a dark version; the app follows Android's dark theme.
package it.rimaturus.edikola

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

/** A strong color (bands, stripes, buttons) and its tint (backgrounds behind text) */
data class Tone(val strong: Color, val tint: Color, val onStrong: Color = Color.White)

class Palette(val dark: Boolean) {
    private fun t(light: Long, lightTint: Long, dark: Long, darkTint: Long) =
        if (this.dark) Tone(Color(dark), Color(darkTint), Color(0xFF111111)) else Tone(Color(light), Color(lightTint))

    val italia = t(0xFFC62828, 0xFFF7D9D9, 0xFFEF9A9A, 0xFF3A2222)
    val mondo = t(0xFF1565C0, 0xFFD6E4F7, 0xFF90CAF9, 0xFF1E2A3A)
    val buone = t(0xFF2E7D32, 0xFFDAEEDB, 0xFFA5D6A7, 0xFF1F3121)
    val scienza = t(0xFF6A1B9A, 0xFFE8D9F1, 0xFFCE93D8, 0xFF2E2236)
    val ink = t(0xFF1C2E4A, 0xFFDCE3EE, 0xFFB5C7E3, 0xFF222A36)
    val giochi = t(0xFFD84315, 0xFFFBE0D3, 0xFFFFAB91, 0xFF3A2620)
    val sudoku = t(0xFF00695C, 0xFFD3ECE8, 0xFF80CBC4, 0xFF1C302D)
    val cruciverba = t(0xFF283593, 0xFFDCE0F5, 0xFF9FA8DA, 0xFF222538)
    val crucipuzzle = t(0xFFAD1457, 0xFFF7D7E5, 0xFFF48FB1, 0xFF38222C)
    val errore = if (dark) Color(0xFFEF9A9A) else Color(0xFFC62828)
    val scritto = if (dark) Color(0xFF90CAF9) else Color(0xFF1A3FA8)
    /** found words in the crucipuzzle, each its own color */
    val found = if (dark) listOf(0xFF6D5A1E, 0xFF2E5530, 0xFF27496D, 0xFF6A2F45, 0xFF6B4A1E, 0xFF4E2E5A, 0xFF1F5450, 0xFF55581F).map { Color(it) }
        else listOf(0xFFFFE082, 0xFFA5D6A7, 0xFF90CAF9, 0xFFF48FB1, 0xFFFFCC80, 0xFFCE93D8, 0xFF80CBC4, 0xFFE6EE9C).map { Color(it) }

    fun section(id: String) = when (id) { "italia" -> italia; "mondo" -> mondo; "buone" -> buone; else -> scienza }

    fun topic(name: String): Color = when (name) {
        "Politica" -> italia.strong
        "Economia e lavoro" -> if (dark) Color(0xFFFFB74D) else Color(0xFFEF6C00)
        "Esteri e conflitti" -> mondo.strong
        "Cronaca" -> if (dark) Color(0xFFBCAAA4) else Color(0xFF5D4037)
        "Salute" -> if (dark) Color(0xFF80CBC4) else Color(0xFF00897B)
        "Scienza e tecnologia" -> scienza.strong
        "Ambiente" -> buone.strong
        "Cultura e spettacoli" -> crucipuzzle.strong
        "Sport" -> if (dark) Color(0xFFFFE082) else Color(0xFFF9A825)
        else -> Color(0xFF9E9E9E)
    }
}

val LocalPalette = staticCompositionLocalOf { Palette(false) }

@Composable
fun EdikolaTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val p = Palette(dark)
    val scheme = if (dark) darkColorScheme(
        primary = p.ink.strong, onPrimary = Color(0xFF111111),
        primaryContainer = p.ink.tint, onPrimaryContainer = Color(0xFFE6E6E6),
        secondaryContainer = p.ink.tint, onSecondaryContainer = Color(0xFFE6E6E6),
        background = Color(0xFF121212), surface = Color(0xFF121212),
        surfaceContainer = Color(0xFF1C1C1C), surfaceContainerHigh = Color(0xFF242424),
    ) else lightColorScheme(
        primary = p.ink.strong, onPrimary = Color.White,
        primaryContainer = p.ink.tint, onPrimaryContainer = p.ink.strong,
        secondaryContainer = p.ink.tint, onSecondaryContainer = p.ink.strong,
        background = Color.White, surface = Color.White,
        surfaceContainer = Color(0xFFF4F5F8), surfaceContainerHigh = Color(0xFFECEEF3),
    )
    androidx.compose.runtime.CompositionLocalProvider(LocalPalette provides p) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}
