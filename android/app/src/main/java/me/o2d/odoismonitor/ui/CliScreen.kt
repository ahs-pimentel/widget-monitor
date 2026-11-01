package me.o2d.odoismonitor.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import me.o2d.odoismonitor.data.Provider
import me.o2d.odoismonitor.data.toInstantOrNull
import java.time.Duration
import java.time.Instant

/** Lista das CLIs com o anel do limite mais alto. */
@Composable
fun CliListScreen(providers: List<Provider>, open: (String) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        providers.forEach { p ->
            Card(Modifier.clickable { open(p.id) }) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    val l = p.topLimit
                    ProviderIcon(p, 36.dp, ring = l?.fraction, ringColor = Palette.severity(l?.fraction ?: 0f))
                    HGap(14.dp)
                    Column(Modifier.weight(1f)) {
                        Text(p.name, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                        Text(p.account ?: Fmt.activity(p.lastActivity.toInstantOrNull()), color = Palette.secondary, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    Column(horizontalAlignment = Alignment.End) {
                        Text(Fmt.tokens(p.today.total), fontWeight = FontWeight.Bold, fontSize = 17.sp)
                        Text(l?.let { "${it.usedPercent.toInt()}% ${it.label.lowercase()}" } ?: "hoje", color = l?.let { Palette.severity(it.fraction) } ?: Palette.secondary, fontSize = 11.sp)
                    }
                }
            }
        }
    }
}

/** Detalhe de uma CLI: limites, hoje, semana e sessões. */
@Composable
fun CliDetailScreen(p: Provider, now: Instant) {
    val tint = Palette.hex(p.tint)
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            ProviderIcon(p, 44.dp)
            HGap(14.dp)
            Column(Modifier.weight(1f)) {
                Text(p.name, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                p.account?.let { Text(it, color = Palette.secondary, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis) }
                Text(Fmt.activity(p.lastActivity.toInstantOrNull()), color = if (p.active) Palette.green else Palette.secondary, fontSize = 12.sp)
            }
            p.plan?.let { Chip(it.uppercase(), Palette.secondary) }
        }

        if (p.limits.isNotEmpty() || p.block != null) {
            Card {
                p.limits.sortedByDescending { it.usedPercent }.forEach { l ->
                    Row(verticalAlignment = Alignment.Bottom) {
                        Text(l.label, fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f))
                        Text("${l.usedPercent.toInt()}%", color = Palette.severity(l.fraction), fontSize = 20.sp, fontWeight = FontWeight.Bold)
                    }
                    Meter(l.fraction, Palette.severity(l.fraction), height = 8.dp)
                    l.forecastAt.toInstantOrNull()?.let {
                        Text("No ritmo atual esgota ${Fmt.until(it, now)} · ${Fmt.time(it)}", color = Palette.orange, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                    }
                    l.resetsAt.toInstantOrNull()?.let { Text("Reinicia ${Fmt.until(it, now)} · ${Fmt.time(it)}", color = Palette.secondary, fontSize = 12.sp) }
                }
                p.block?.let { b ->
                    val end = b.endsAt.toInstantOrNull()
                    val elapsed = end?.let { 1f - (Duration.between(now, it).seconds.coerceAtLeast(0) / (5 * 3600f)) } ?: 0f
                    Row(verticalAlignment = Alignment.Bottom) {
                        Text("Bloco de 5 h", fontWeight = FontWeight.Medium)
                        HGap(6.dp)
                        Text("estimado", color = Palette.secondary, fontSize = 12.sp, modifier = Modifier.weight(1f))
                        Text(Fmt.tokens(b.tokens), fontSize = 18.sp, fontWeight = FontWeight.Bold)
                    }
                    Meter(elapsed, tint, height = 8.dp)
                    Text("Termina ${Fmt.until(end, now)} · ${Fmt.time(end)}", color = Palette.secondary, fontSize = 12.sp)
                }
            }
        }

        Card {
            SectionTitle("Hoje", p.topModel)
            val t = p.today
            if (t.total == 0L) {
                Text("Nenhum uso hoje", color = Palette.secondary, fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
            } else {
                Row(verticalAlignment = Alignment.Bottom) {
                    Text(Fmt.tokens(t.total), fontSize = 32.sp, fontWeight = FontWeight.Bold)
                    HGap(6.dp)
                    Text("tokens", color = Palette.secondary, modifier = Modifier.weight(1f).padding(bottom = 6.dp))
                    p.costToday?.let { Text(Fmt.usd(it), color = Palette.green, fontWeight = FontWeight.SemiBold) }
                }
                Text("${p.messagesToday} respostas · ${p.sessionsToday} ${if (p.sessionsToday == 1) "sessão" else "sessões"}", color = Palette.secondary, fontSize = 12.sp)
                val parts = listOf(
                    Triple("Entrada", t.input, Palette.blue),
                    Triple("Saída", t.output, Palette.orange),
                    Triple("Cache novo", t.cacheWrite, Color(0xFF64D2FF)),
                    Triple("Cache lido", t.cacheRead, Color(0xFF636366)),
                )
                val total = parts.sumOf { it.second }.coerceAtLeast(1)
                Canvas(Modifier.fillMaxWidth().height(10.dp)) {
                    var x = 0f
                    parts.filter { it.second > 0 }.forEach { (_, v, c) ->
                        val w = (size.width * v / total).coerceAtLeast(3f)
                        drawRect(c, Offset(x, 0f), Size(w - 2f, size.height))
                        x += w
                    }
                }
                parts.chunked(2).forEach { row ->
                    Row {
                        row.forEach { (label, v, c) ->
                            Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically) {
                                Dot(c, 7.dp); HGap(6.dp)
                                Text(label, color = Palette.secondary, fontSize = 12.sp, modifier = Modifier.weight(1f))
                                Text(Fmt.tokens(v), fontWeight = FontWeight.SemiBold, fontSize = 12.sp)
                                HGap(12.dp)
                            }
                        }
                    }
                }
            }
        }

        Card {
            val average = p.daily.sum() / 7
            SectionTitle("Últimos 7 dias", "${Fmt.tokens(p.weekTotal)} · média ${Fmt.tokens(average)}/dia")
            val max = (p.daily.maxOrNull() ?: 0L).coerceAtLeast(1L)
            Bars(p.daily.map { it.toFloat() / max }, tint, Modifier.fillMaxWidth().height(70.dp), highlightLast = true)
            Row { Fmt.weekdays().forEachIndexed { i, d -> Text(d, color = if (i == 6) Palette.text else Palette.secondary, fontSize = 11.sp, fontWeight = if (i == 6) FontWeight.Bold else FontWeight.Normal, modifier = Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.Center) } }
        }

        if (p.history.size == 30 && p.history.count { it > 0 } > 7) {
            Card {
                val total = p.history.sum()
                SectionTitle("30 dias", "${Fmt.tokens(total)} · média ${Fmt.tokens(total / 30)}/dia")
                val max = (p.history.maxOrNull() ?: 0L).coerceAtLeast(1L)
                Bars(p.history.map { it.toFloat() / max }, tint, Modifier.fillMaxWidth().height(56.dp), highlightLast = true)
            }
        }

        if (p.sessions.isNotEmpty()) {
            Card {
                SectionTitle("Sessões recentes")
                val max = p.sessions.maxOf { it.tokens }.coerceAtLeast(1L)
                p.sessions.forEach { s ->
                    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            if (s.active) { Dot(Palette.green, 6.dp); HGap(6.dp) }
                            Text(s.project ?: "Sessão ${s.id.take(6)}", fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(Fmt.tokens(s.tokens), fontWeight = FontWeight.SemiBold)
                        }
                        Text(listOfNotNull(s.model, "${s.messages} resp.", Fmt.relative(s.last.toInstantOrNull(), now)).joinToString(" · "), color = Palette.secondary, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Meter(s.tokens.toFloat() / max, tint.copy(alpha = 0.8f), height = 3.dp)
                    }
                }
            }
        }
        p.note?.let { Text(it, color = Palette.secondary, fontSize = 12.sp) }
    }
}
