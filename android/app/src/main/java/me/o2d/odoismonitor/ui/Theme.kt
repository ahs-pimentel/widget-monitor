package me.o2d.odoismonitor.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/** Paleta do oDois Monitor (a mesma do Mac). */
object Palette {
    val background = Color(0xFF0B0B14)
    val surface = Color(0xFF15151F)
    val surfaceHigh = Color(0xFF1E1E2B)
    val outline = Color(0xFF2A2A3A)
    val teal = Color(0xFF0D9EC7)
    val indigo = Color(0xFF544CEB)
    val green = Color(0xFF34C759)
    val orange = Color(0xFFFF9F0A)
    val red = Color(0xFFFF453A)
    val yellow = Color(0xFFFFD60A)
    val purple = Color(0xFFBF5AF2)
    val blue = Color(0xFF0A84FF)
    val text = Color(0xFFF2F2F7)
    val secondary = Color(0xFF9A9AAE)
    val hero = Brush.linearGradient(listOf(teal, indigo))

    fun severity(fraction: Float): Color = when {
        fraction >= 0.9f -> red
        fraction >= 0.7f -> orange
        else -> green
    }

    fun hex(value: String): Color = runCatching {
        Color(android.graphics.Color.parseColor(value))
    }.getOrDefault(secondary)

    /** Cor estável por projeto (mesmo hash do Mac). */
    fun project(slug: String): Color {
        var sum = 7u
        for (ch in slug) sum = sum * 31u + ch.code.toUInt()
        return Color.hsv((sum % 360u).toFloat(), 0.6f, 0.85f)
    }
}

private val scheme = darkColorScheme(
    primary = Palette.teal,
    secondary = Palette.indigo,
    background = Palette.background,
    surface = Palette.surface,
    surfaceVariant = Palette.surfaceHigh,
    surfaceContainer = Palette.surface,
    surfaceContainerHigh = Palette.surfaceHigh,
    onBackground = Palette.text,
    onSurface = Palette.text,
    onSurfaceVariant = Palette.secondary,
    outline = Palette.outline,
    error = Palette.red,
)

@Composable
fun MonitorTheme(content: @Composable () -> Unit) {
    // Tema escuro sempre: é um painel de monitoramento, como o notch do Mac.
    @Suppress("UNUSED_VARIABLE") val dark = isSystemInDarkTheme()
    MaterialTheme(
        colorScheme = scheme,
        typography = Typography(
            headlineLarge = TextStyle(fontSize = 30.sp, fontWeight = FontWeight.Bold),
            titleMedium = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.SemiBold),
            labelSmall = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.6.sp),
        ),
        content = content,
    )
}
