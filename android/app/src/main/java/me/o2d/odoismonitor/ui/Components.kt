package me.o2d.odoismonitor.ui

import android.graphics.Bitmap
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import me.o2d.odoismonitor.data.MonitorRepository
import me.o2d.odoismonitor.data.Provider

/** Cartão padrão (fundo um tom acima, cantos 18). */
@Composable
fun Card(modifier: Modifier = Modifier, brush: Brush? = null, content: @Composable ColumnScope.() -> Unit) {
    val shape = RoundedCornerShape(18.dp)
    Column(
        modifier
            .fillMaxWidth()
            .clip(shape)
            .then(if (brush != null) Modifier.background(brush) else Modifier.background(Palette.surface))
            .border(1.dp, Color.White.copy(alpha = 0.06f), shape)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
        content = content,
    )
}

@Composable
fun SectionTitle(title: String, detail: String? = null, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(title.uppercase(), style = MaterialTheme.typography.labelSmall, color = Palette.secondary, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
        if (detail != null) Text(detail, fontSize = 11.sp, color = Palette.secondary)
    }
}

/** Barra de progresso em cápsula. */
@Composable
fun Meter(fraction: Float, color: Color, modifier: Modifier = Modifier, height: Dp = 6.dp) {
    Canvas(modifier.fillMaxWidth().height(height)) {
        val r = CornerRadius(size.height / 2)
        drawRoundRect(Color.White.copy(alpha = 0.1f), cornerRadius = r)
        val w = size.width * fraction.coerceIn(0f, 1f)
        if (w > 0) drawRoundRect(color, size = Size(w.coerceAtLeast(size.height), size.height), cornerRadius = r)
    }
}

/** Anel de progresso com conteúdo no centro. */
@Composable
fun Ring(fraction: Float, color: Color, size: Dp, stroke: Dp = 6.dp, content: @Composable () -> Unit = {}) {
    Box(Modifier.size(size), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val s = stroke.toPx()
            val inset = s / 2
            val arc = Size(this.size.width - s, this.size.height - s)
            drawArc(Color.White.copy(alpha = 0.12f), 0f, 360f, false, Offset(inset, inset), arc, style = Stroke(s))
            drawArc(color, -90f, 360f * fraction.coerceIn(0f, 1f), false, Offset(inset, inset), arc, style = Stroke(s, cap = StrokeCap.Round))
        }
        content()
    }
}

/** Barras verticais (histórico ou dias da semana). */
@Composable
fun Bars(values: List<Float>, color: Color, modifier: Modifier = Modifier, highlightLast: Boolean = false) {
    Canvas(modifier) {
        if (values.isEmpty()) return@Canvas
        val gap = 3.dp.toPx()
        val w = (size.width - gap * (values.size - 1)) / values.size
        values.forEachIndexed { i, v ->
            val h = (size.height * v.coerceIn(0f, 1f)).coerceAtLeast(2.dp.toPx())
            val alpha = if (!highlightLast || i == values.lastIndex) 1f else 0.4f
            drawRoundRect(color.copy(alpha = alpha), Offset(i * (w + gap), size.height - h), Size(w, h), CornerRadius(3.dp.toPx()))
        }
    }
}

@Composable
fun Chip(text: String, color: Color) {
    Text(
        text,
        fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = color,
        modifier = Modifier.clip(CircleShape).background(color.copy(alpha = 0.16f)).padding(horizontal = 8.dp, vertical = 3.dp),
    )
}

/** Imagem vinda do Mac (ícone/avatar), carregada uma vez e guardada em memória. */
@Composable
fun RemoteImage(path: String, size: Dp, shape: androidx.compose.ui.graphics.Shape, fallback: @Composable () -> Unit) {
    val context = androidx.compose.ui.platform.LocalContext.current
    var bitmap by remember(path) { mutableStateOf<Bitmap?>(null) }
    var loaded by remember(path) { mutableStateOf(false) }
    LaunchedEffect(path) {
        bitmap = MonitorRepository.get(context).image(path)
        loaded = true
    }
    val bmp = bitmap
    if (bmp != null) {
        Image(bmp.asImageBitmap(), null, Modifier.size(size).clip(shape))
    } else if (loaded) {
        fallback()
    } else {
        Box(Modifier.size(size).clip(shape).background(Palette.surfaceHigh))
    }
}

/** Ícone da CLI: o do app no Mac, ou a sigla sobre a cor dela. */
@Composable
fun ProviderIcon(p: Provider, size: Dp = 32.dp, ring: Float? = null, ringColor: Color = Palette.green) {
    val shape = RoundedCornerShape(size * 0.26f)
    val icon: @Composable () -> Unit = {
        val fallback: @Composable () -> Unit = {
            Box(
                Modifier.size(size).clip(shape).background(Brush.verticalGradient(listOf(Palette.hex(p.tint), Palette.hex(p.tint).copy(alpha = 0.7f)))),
                contentAlignment = Alignment.Center,
            ) {
                Text(p.monogram ?: p.name.take(1), color = Color.White, fontWeight = FontWeight.Black, fontSize = (size.value * 0.36f).sp)
            }
        }
        if (p.hasIcon) RemoteImage("/v1/icons/${p.id}.png", size, shape, fallback) else fallback()
    }
    Box(contentAlignment = Alignment.BottomEnd) {
        if (ring != null) {
            Ring(ring, ringColor, size + 10.dp, 2.5.dp) { icon() }
        } else {
            icon()
        }
        if (p.active) {
            Box(Modifier.size(size * 0.3f).clip(CircleShape).background(Palette.background).padding(2.dp).clip(CircleShape).background(Palette.green))
        }
    }
}

@Composable
fun Dot(color: Color, size: Dp = 7.dp) {
    Box(Modifier.size(size).clip(CircleShape).background(color))
}

@Composable
fun Gap(h: Dp = 8.dp) = Spacer(Modifier.height(h))

@Composable
fun HGap(w: Dp = 8.dp) = Spacer(Modifier.width(w))
