package me.o2d.odoismonitor.ui

import android.content.Intent
import android.net.Uri
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.EmojiEvents
import androidx.compose.material.icons.rounded.ExpandMore
import androidx.compose.material.icons.rounded.Notifications
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import me.o2d.odoismonitor.data.ActivityType
import me.o2d.odoismonitor.data.MonitorRepository
import me.o2d.odoismonitor.data.Sea
import me.o2d.odoismonitor.data.SeaTask
import me.o2d.odoismonitor.data.TaskTimer
import me.o2d.odoismonitor.data.toInstantOrNull
import java.time.Instant
import java.time.LocalDate
import java.util.Locale

@Composable
fun TasksScreen(sea: Sea, now: Instant, receivedAt: Instant, repo: MonitorRepository) {
    val context = LocalContext.current
    var finishing by remember { mutableStateOf<TaskTimer?>(null) }
    var discarding by remember { mutableStateOf<TaskTimer?>(null) }
    val collapsed = remember { mutableStateListOf<String>() }
    fun open(url: String?) { url?.let { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(it))) } }

    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        // Cabeçalho: avatar, nome e contagem.
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(52.dp).clip(CircleShape).background(Palette.hero).padding(2.dp)) {
                RemoteImage("/v1/avatar.png", 48.dp, CircleShape) {
                    Box(Modifier.size(48.dp).clip(CircleShape).background(Palette.hero), contentAlignment = Alignment.Center) {
                        Text(initials(sea.accountName), color = Color.White, fontWeight = FontWeight.Bold)
                    }
                }
            }
            HGap(12.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(sea.accountName ?: "Tarefas", fontSize = 18.sp, fontWeight = FontWeight.Bold)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    val doing = sea.tasks.count { it.inProgress }
                    Chip("$doing em andamento", Palette.blue)
                    Chip("${sea.tasks.size - doing} a iniciar", Palette.secondary)
                }
            }
            if (sea.loading) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
        }

        sea.message?.let { Text("✓ $it", color = Palette.green, fontWeight = FontWeight.SemiBold, fontSize = 13.sp) }
        sea.ranking?.let { r ->
            Card(brush = Brush.horizontalGradient(listOf(Palette.orange.copy(alpha = 0.22f), Palette.orange.copy(alpha = 0.05f)))) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(36.dp).clip(CircleShape).background(Brush.verticalGradient(listOf(Palette.yellow, Palette.orange))), contentAlignment = Alignment.Center) {
                        Icon(Icons.Rounded.EmojiEvents, null, tint = Color.White)
                    }
                    HGap(12.dp)
                    Text(r.position?.let { "${it}º" + (r.total?.let { t -> " de $t" } ?: "") } ?: "Ranking ${r.year}", fontWeight = FontWeight.Bold, fontSize = 18.sp, modifier = Modifier.weight(1f))
                    Text("${Fmt.number(r.score)} pts", fontWeight = FontWeight.Black, fontSize = 18.sp)
                }
            }
        }

        // Cronômetro em destaque.
        sea.running?.let { t -> Hero(t, now, receivedAt, repo, onFinish = { finishing = t }, onDiscard = { discarding = t }, open = { open(t.task.url) }) }

        // Pausados.
        val paused = sea.timers.filter { !it.running }
        if (paused.isNotEmpty()) {
            Card {
                SectionTitle("Pausados", "${paused.size}")
                paused.forEach { t ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f).clickable { open(t.task.url) }) {
                            Text(t.task.title, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(t.task.projectName, color = Palette.secondary, fontSize = 11.sp, maxLines = 1)
                        }
                        Text(Fmt.clock(t.elapsed), fontWeight = FontWeight.Bold)
                        IconButton(onClick = { repo.act { it.startTask(t.task.id) } }) { Icon(Icons.Rounded.PlayArrow, "Retomar", tint = Palette.teal) }
                        IconButton(onClick = { finishing = t }) { Icon(Icons.Rounded.Check, "Finalizar", tint = Palette.green) }
                    }
                }
            }
        }

        // Notificações.
        if (sea.notifications.isNotEmpty()) {
            Card {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Rounded.Notifications, null, tint = Palette.teal, modifier = Modifier.size(16.dp)); HGap(6.dp)
                    SectionTitle("Notificações", modifier = Modifier.weight(1f))
                    Text("${sea.notifications.size}", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold, modifier = Modifier.clip(CircleShape).background(Palette.red).padding(horizontal = 7.dp, vertical = 1.dp))
                }
                sea.notifications.forEach { n ->
                    Row(Modifier.clip(RoundedCornerShape(12.dp)).background(Palette.teal.copy(alpha = 0.1f)).padding(10.dp), verticalAlignment = Alignment.Top) {
                        Column(Modifier.weight(1f).clickable { open(n.url); repo.act { it.markRead(n.id) } }) {
                            Text(n.title, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
                            Text(n.body, color = Palette.secondary, fontSize = 12.sp, maxLines = 3, overflow = TextOverflow.Ellipsis)
                            Text(Fmt.relative(n.createdAt.toInstantOrNull(), now), color = Palette.secondary, fontSize = 10.sp)
                        }
                        IconButton(onClick = { repo.act { it.markRead(n.id) } }) { Icon(Icons.Rounded.Check, "Marcar como lida", tint = Palette.secondary) }
                    }
                }
            }
        }

        // Tarefas por projeto (recolhíveis).
        val running = sea.timers.map { it.task.id }.toSet()
        val groups = sea.tasks.filter { it.id !in running }.groupBy { it.projectSlug }.toList().sortedBy { it.second.first().projectName }
        if (groups.isEmpty() && sea.timers.isEmpty() && !sea.loading) {
            Card { Text("Tudo em dia ✓", fontWeight = FontWeight.Bold); Text("Nenhuma tarefa em aberto ou em andamento.", color = Palette.secondary) }
        }
        groups.forEach { (slug, tasks) ->
            val color = Palette.project(slug)
            val open = slug !in collapsed
            Card {
                Row(Modifier.clickable { if (open) collapsed.add(slug) else collapsed.remove(slug) }, verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.width(4.dp).height(16.dp).clip(CircleShape).background(color)); HGap(8.dp)
                    Text(tasks.first().projectName, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Chip("${tasks.size}", color)
                    Icon(Icons.Rounded.ExpandMore, null, tint = Palette.secondary, modifier = Modifier.rotate(if (open) 0f else -90f))
                }
                AnimatedVisibility(open) {
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) { tasks.forEach { TaskRow(it, color, repo, open = { open(it.url) }) } }
                }
            }
        }
        sea.error?.let { Text("⚠ $it", color = Palette.orange, fontSize = 12.sp) }
    }

    finishing?.let { t -> FinishSheet(t, now, receivedAt, repo, onClose = { finishing = null }) }
    discarding?.let { t ->
        AlertDialog(
            onDismissRequest = { discarding = null },
            title = { Text("Descartar o cronômetro?") },
            text = { Text("${Fmt.clock(t.elapsedAt(now, receivedAt))} de ${t.task.title} não serão registrados no Dashboard.") },
            confirmButton = { TextButton(onClick = { repo.act("Cronômetro descartado") { it.discardTimer(t.task.id) }; discarding = null }) { Text("Descartar", color = Palette.red) } },
            dismissButton = { TextButton(onClick = { discarding = null }) { Text("Cancelar") } },
            containerColor = Palette.surfaceHigh,
        )
    }
}

@Composable
private fun Hero(t: TaskTimer, now: Instant, receivedAt: Instant, repo: MonitorRepository, onFinish: () -> Unit, onDiscard: () -> Unit, open: () -> Unit) {
    val elapsed = t.elapsedAt(now, receivedAt)
    Card(brush = Palette.hero) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(7.dp).clip(CircleShape).background(Color.White.copy(alpha = if ((now.epochSecond % 2) == 0L) 1f else 0.35f)))
            HGap(6.dp)
            Text("GRAVANDO", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Black, letterSpacing = 1.sp, modifier = Modifier.weight(1f))
            Text(t.task.projectName, color = Color.White.copy(alpha = 0.85f), fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Ring(((elapsed % 3600) / 3600).toFloat().coerceAtLeast(0.01f), Color.White, 64.dp, 5.dp) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("${(elapsed / 3600).toInt()}", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 20.sp)
                    Text("h", color = Color.White.copy(alpha = 0.8f), fontSize = 10.sp)
                }
            }
            HGap(16.dp)
            Column(Modifier.weight(1f).clickable(onClick = open)) {
                Text(Fmt.clock(elapsed), color = Color.White, fontSize = 40.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Default)
                Text(t.task.title, color = Color.White, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            if (t.task.busy) {
                CircularProgressIndicator(Modifier.size(20.dp), color = Color.White, strokeWidth = 2.dp)
                Text("Enviando ao Dashboard…", color = Color.White)
            } else {
                Button(onClick = { repo.act { it.pauseTimer(t.task.id) } }, colors = ButtonDefaults.buttonColors(containerColor = Color.White.copy(alpha = 0.2f), contentColor = Color.White)) {
                    Icon(Icons.Rounded.Pause, null); HGap(4.dp); Text("Pausar")
                }
                Button(onClick = onFinish, colors = ButtonDefaults.buttonColors(containerColor = Color.White, contentColor = Palette.indigo)) {
                    Icon(Icons.Rounded.Check, null); HGap(4.dp); Text("Finalizar", fontWeight = FontWeight.Bold)
                }
            }
            Box(Modifier.weight(1f))
            IconButton(onClick = onDiscard) { Icon(Icons.Rounded.Delete, "Descartar", tint = Color.White.copy(alpha = 0.85f)) }
        }
    }
}

@Composable
private fun TaskRow(task: SeaTask, color: Color, repo: MonitorRepository, open: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Color.White.copy(alpha = 0.04f)).border(1.dp, Color.White.copy(alpha = 0.04f), RoundedCornerShape(12.dp)).padding(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text("#${task.number}", color = color, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold, fontSize = 12.sp,
            modifier = Modifier.clip(RoundedCornerShape(6.dp)).background(color.copy(alpha = 0.16f)).padding(horizontal = 6.dp, vertical = 3.dp))
        HGap(10.dp)
        Column(Modifier.weight(1f).clickable(onClick = open)) {
            Text(task.subject, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(if (task.inProgress) "Em andamento" else "Não iniciado", color = if (task.inProgress) Palette.blue else Palette.secondary, fontSize = 11.sp)
        }
        if (task.busy) {
            CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
        } else {
            Box(Modifier.size(36.dp).clip(CircleShape).background(Palette.hero).clickable { repo.act { it.startTask(task.id) } }, contentAlignment = Alignment.Center) {
                Icon(Icons.Rounded.PlayArrow, "Iniciar", tint = Color.White)
            }
        }
    }
}

/** Finalizar: horas (editáveis), dia, tipo de atividade e comentário; o Mac grava no Dashboard. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FinishSheet(t: TaskTimer, now: Instant, receivedAt: Instant, repo: MonitorRepository, onClose: () -> Unit) {
    val suggested = Math.round(t.elapsedAt(now, receivedAt) / 36.0) / 100.0
    var hours by rememberSaveable { mutableStateOf(Fmt.number(suggested.coerceAtLeast(0.01))) }
    var dayOffset by rememberSaveable { mutableStateOf(0) }
    var comment by rememberSaveable { mutableStateOf("") }
    var types by remember { mutableStateOf<List<ActivityType>>(emptyList()) }
    var selected by remember { mutableStateOf<ActivityType?>(null) }
    var expanded by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(t.task.projectSlug) {
        runCatching { repo.client?.activityTypes(t.task.projectSlug) }.onSuccess { result ->
            types = result?.data.orEmpty()
            val preferred = result?.preferred ?: t.preferredActivityType
            selected = types.firstOrNull { it.id == preferred } ?: types.firstOrNull { it.label == "Desenvolvimento" } ?: types.firstOrNull()
        }.onFailure { error = it.message }
    }

    ModalBottomSheet(onDismissRequest = onClose, containerColor = Palette.surfaceHigh) {
        Column(Modifier.padding(horizontal = 20.dp).padding(bottom = 28.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text("Registrar horas", fontSize = 20.sp, fontWeight = FontWeight.Bold)
            Text("${t.task.title} · ${t.task.projectName}", color = Palette.secondary, maxLines = 2)
            OutlinedTextField(
                value = hours, onValueChange = { hours = it }, label = { Text("Horas") },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), singleLine = true, modifier = Modifier.fillMaxWidth(),
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(0 to "Hoje", 1 to "Ontem", 2 to "Anteontem").forEach { (offset, label) ->
                    FilterChip(selected = dayOffset == offset, onClick = { dayOffset = offset }, label = { Text(label) })
                }
            }
            ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
                OutlinedTextField(
                    value = selected?.label ?: "Carregando tipos…", onValueChange = {}, readOnly = true, label = { Text("Atividade") },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded) },
                    modifier = Modifier.fillMaxWidth().menuAnchor(MenuAnchorType.PrimaryNotEditable),
                )
                ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                    types.forEach { type -> DropdownMenuItem(text = { Text(type.label) }, onClick = { selected = type; expanded = false }) }
                }
            }
            OutlinedTextField(value = comment, onValueChange = { comment = it }, label = { Text("Comentário (opcional)") }, modifier = Modifier.fillMaxWidth(), minLines = 2)
            error?.let { Text(it, color = Palette.red, fontSize = 13.sp) }
            Button(
                onClick = {
                    val h = hours.replace(",", ".").toDoubleOrNull()
                    val type = selected
                    when {
                        h == null || h <= 0 || h > 24 -> error = "Informe as horas entre 0 e 24 (ex.: 1,5)."
                        type == null -> error = "Escolha o tipo de atividade."
                        else -> {
                            val date = LocalDate.now().minusDays(dayOffset.toLong()).toString()
                            repo.act("${Fmt.number(h)} h registradas em ${t.task.title}") { it.finishTimer(t.task.id, h, date, type.id, comment.trim()) }
                            onClose()
                        }
                    }
                },
                modifier = Modifier.fillMaxWidth().height(52.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Palette.teal, contentColor = Color.White),
            ) { Text("Registrar no Dashboard", fontWeight = FontWeight.Bold) }
        }
    }
}

private fun initials(name: String?): String {
    val parts = name.orEmpty().split(" ").filter { it.isNotBlank() }
    return listOfNotNull(parts.firstOrNull()?.first(), parts.drop(1).lastOrNull()?.first()).joinToString("").uppercase(Locale.ROOT).ifEmpty { "?" }
}

