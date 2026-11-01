package me.o2d.odoismonitor.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Timer
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import me.o2d.odoismonitor.data.MonitorState
import me.o2d.odoismonitor.data.TaskTimer
import me.o2d.odoismonitor.data.toInstantOrNull
import java.time.Instant

@Composable
fun OverviewScreen(state: MonitorState, now: Instant, receivedAt: Instant, openCli: (String) -> Unit, openTasks: () -> Unit, openSystem: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        // Totais do dia.
        Card {
            Row(verticalAlignment = Alignment.Bottom) {
                Column(Modifier.weight(1f)) {
                    Text("Hoje", color = Palette.secondary, fontSize = 13.sp)
                    Row(verticalAlignment = Alignment.Bottom) {
                        Text(Fmt.tokens(state.todayTotal), fontSize = 34.sp, fontWeight = FontWeight.Bold)
                        HGap(6.dp)
                        Text("tokens", color = Palette.secondary, fontSize = 14.sp, modifier = Modifier.padding(bottom = 6.dp))
                    }
                }
                Column(horizontalAlignment = Alignment.End) {
                    val active = state.activeSessions
                    Chip(if (active == 0) "nenhuma sessão ativa" else "$active ${if (active == 1) "sessão ativa" else "sessões ativas"}", if (active == 0) Palette.secondary else Palette.green)
                }
            }
            state.topLimit?.takeIf { it.second.usedPercent >= 80 }?.let { (p, l) ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Rounded.Warning, null, tint = Palette.severity(l.fraction), modifier = Modifier.padding(end = 6.dp))
                    Text("${p.name}: ${l.label.lowercase()} em ${l.usedPercent.toInt()}%", color = Palette.severity(l.fraction), fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
                }
                l.forecastAt.toInstantOrNull()?.let {
                    Text("No ritmo atual esgota ${Fmt.until(it, now)} (${Fmt.time(it)})", color = Palette.orange, fontSize = 12.sp)
                }
            }
        }

        state.sea?.running?.let { RunningStrip(it, now, receivedAt, openTasks) }

        // CLIs.
        Card {
            SectionTitle("CLIs")
            val sorted = state.providers.sortedWith(compareBy({ -(it.topLimit?.usedPercent ?: 0.0) }, { if (it.active) 0 else 1 }))
            sorted.forEachIndexed { i, p ->
                if (i > 0) HorizontalDivider(color = Palette.outline)
                Column(Modifier.fillMaxWidth().clickable { openCli(p.id) }.padding(vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        ProviderIcon(p, 30.dp)
                        HGap(12.dp)
                        Column(Modifier.weight(1f)) {
                            Text(p.name, fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
                            Text(Fmt.activity(p.lastActivity.toInstantOrNull()), color = if (p.active) Palette.green else Palette.secondary, fontSize = 12.sp)
                        }
                        Column(horizontalAlignment = Alignment.End) {
                            Text(Fmt.tokens(p.today.total), fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
                            p.costToday?.let { Text(Fmt.usd(it), color = Palette.green, fontSize = 11.sp) }
                        }
                    }
                    p.topLimit?.let { l ->
                        Row(Modifier.padding(start = 42.dp), verticalAlignment = Alignment.CenterVertically) {
                            Meter(l.fraction, Palette.severity(l.fraction), Modifier.weight(1f), 5.dp)
                            HGap(8.dp)
                            Text("${l.label.lowercase()} ${l.usedPercent.toInt()}%", color = Palette.severity(l.fraction), fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
                        }
                    }
                }
            }
        }

        // Sistema.
        Card(Modifier.clickable(onClick = openSystem)) {
            SectionTitle("Mac · ${state.host}", "${state.processes.size} processos de CLI")
            val s = state.system
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Gauge("CPU", s.cpu.toFloat(), Palette.blue, Modifier.weight(1f))
                Gauge("RAM", s.ramFraction, if (s.pressureLevel == "normal") Palette.purple else pressureColor(s.pressureLevel), Modifier.weight(1f))
                Column(Modifier.weight(1f)) {
                    Text("Pressão", color = Palette.secondary, fontSize = 12.sp)
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Dot(pressureColor(s.pressureLevel)); HGap(6.dp)
                        Text(pressureLabel(s.pressureLevel), fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                    }
                }
            }
        }
    }
}

@Composable
private fun Gauge(label: String, fraction: Float, color: Color, modifier: Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row { Text(label, color = Palette.secondary, fontSize = 12.sp, modifier = Modifier.weight(1f)); Text(Fmt.percent(fraction), fontWeight = FontWeight.SemiBold, fontSize = 12.sp) }
        Meter(fraction, color, height = 5.dp)
    }
}

@Composable
private fun RunningStrip(t: TaskTimer, now: Instant, receivedAt: Instant, open: () -> Unit) {
    Card(Modifier.clickable(onClick = open), brush = Palette.hero) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Rounded.Timer, null, tint = Color.White)
            HGap(10.dp)
            Column(Modifier.weight(1f)) {
                Text(t.task.title, color = Color.White, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(t.task.projectName, color = Color.White.copy(alpha = 0.8f), fontSize = 12.sp, maxLines = 1)
            }
            Text(Fmt.clock(t.elapsedAt(now, receivedAt)), color = Color.White, fontSize = 24.sp, fontWeight = FontWeight.Bold)
        }
    }
}

fun pressureColor(level: String): Color = when (level) {
    "critical" -> Palette.red
    "warning" -> Palette.yellow
    else -> Palette.green
}

fun pressureLabel(level: String): String = when (level) {
    "critical" -> "Crítica"
    "warning" -> "Atenção"
    else -> "Normal"
}
