package me.o2d.odoismonitor.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.StopCircle
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import me.o2d.odoismonitor.data.CliProcess
import me.o2d.odoismonitor.data.MonitorState
import me.o2d.odoismonitor.data.toInstantOrNull

@Composable
fun SystemScreen(state: MonitorState, stop: (CliProcess, Boolean) -> Unit) {
    val s = state.system
    var confirm by remember { mutableStateOf<CliProcess?>(null) }

    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Card {
            SectionTitle(state.host, "atualiza a cada 2 s")
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                Big("CPU", s.cpu.toFloat(), Palette.blue, "")
                Big("RAM", s.ramFraction, if (s.pressureLevel == "normal") Palette.purple else pressureColor(s.pressureLevel), "de ${Fmt.bytes(s.ramTotal)}")
                Big("GPU", (s.gpu ?: 0.0).toFloat(), Palette.orange, "")
            }
        }
        Card {
            Row(verticalAlignment = Alignment.CenterVertically) {
                SectionTitle("Pressão de memória", modifier = Modifier.weight(1f))
                Dot(pressureColor(s.pressureLevel)); HGap(6.dp)
                Text("${pressureLabel(s.pressureLevel)} · ${(s.pressure * 100).toInt()}%", color = pressureColor(s.pressureLevel), fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
            }
            Bars(s.pressureHistory.map { it.toFloat() }, pressureColor(s.pressureLevel), Modifier.fillMaxWidth().height(40.dp))
            Text("Swap ${Fmt.bytes(s.swapUsed)} de ${Fmt.bytes(s.swapTotal)}", color = Palette.secondary, fontSize = 12.sp)
            SectionTitle("CPU · últimos 2 min")
            Bars(s.cpuHistory.map { it.toFloat() }, Palette.blue, Modifier.fillMaxWidth().height(32.dp))
        }
        Card {
            val bg = state.processes.count { it.background }
            SectionTitle("Processos das CLIs", if (state.processes.isEmpty()) null else "${state.processes.size} · $bg em 2º plano")
            if (state.processes.isEmpty()) Text("Nenhuma CLI de LLM rodando agora.", color = Palette.secondary, fontSize = 13.sp)
            state.processes.forEachIndexed { i, p ->
                if (i > 0) HorizontalDivider(color = Palette.outline)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(p.project ?: p.cliName, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                            if (p.background) { HGap(6.dp); Chip("2º plano", Palette.orange) }
                        }
                        Text(
                            listOfNotNull("PID ${p.pid}", p.cliName, Fmt.relative(p.startedAt.toInstantOrNull()).removePrefix("há "), "${p.cpu.toInt()}% CPU", Fmt.bytes(p.memory)).joinToString(" · "),
                            color = Palette.secondary, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis,
                        )
                    }
                    if (p.stopping) {
                        TextButton(onClick = { stop(p, true) }) { Text("Forçar", color = Palette.red, fontWeight = FontWeight.Bold) }
                    } else {
                        IconButton(onClick = { confirm = p }) { Icon(Icons.Rounded.StopCircle, "Parar", tint = Palette.secondary) }
                    }
                }
            }
        }
    }

    confirm?.let { p ->
        AlertDialog(
            onDismissRequest = { confirm = null },
            title = { Text("Parar o processo ${p.pid}?") },
            text = {
                Text("${p.cliName}${p.project?.let { " · $it" } ?: ""}\n\n\"Parar\" pede para encerrar (SIGTERM); \"Forçar\" encerra na hora (SIGKILL). O trabalho em andamento nessa sessão pode ser perdido.")
            },
            confirmButton = { TextButton(onClick = { stop(p, false); confirm = null }) { Text("Parar", color = Palette.red) } },
            dismissButton = {
                Row {
                    TextButton(onClick = { stop(p, true); confirm = null }) { Text("Forçar", color = Palette.red) }
                    TextButton(onClick = { confirm = null }) { Text("Cancelar") }
                }
            },
            containerColor = Palette.surfaceHigh,
        )
    }
}

@Composable
private fun Big(label: String, fraction: Float, color: Color, detail: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Ring(fraction, color, 76.dp, 7.dp) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(Fmt.percent(fraction), fontWeight = FontWeight.Bold, fontSize = 17.sp)
                Text(label, color = Palette.secondary, fontSize = 10.sp, fontWeight = FontWeight.SemiBold)
            }
        }
        if (detail.isNotEmpty()) Text(detail, color = Palette.secondary, fontSize = 11.sp)
    }
}

