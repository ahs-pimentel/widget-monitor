package me.o2d.odoismonitor

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.Dashboard
import androidx.compose.material.icons.rounded.Memory
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Terminal
import androidx.compose.material.icons.rounded.Timer
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.delay
import me.o2d.odoismonitor.data.Connection
import me.o2d.odoismonitor.data.MonitorRepository
import me.o2d.odoismonitor.ui.CliDetailScreen
import me.o2d.odoismonitor.ui.CliListScreen
import me.o2d.odoismonitor.ui.Dot
import me.o2d.odoismonitor.ui.HGap
import me.o2d.odoismonitor.ui.MonitorTheme
import me.o2d.odoismonitor.ui.OverviewScreen
import me.o2d.odoismonitor.ui.PairScreen
import me.o2d.odoismonitor.ui.Palette
import me.o2d.odoismonitor.ui.SystemScreen
import me.o2d.odoismonitor.ui.TasksScreen
import me.o2d.odoismonitor.widget.MonitorWidget
import java.time.Instant

private enum class Tab(val label: String) { Overview("Geral"), Clis("CLIs"), System("Mac"), Tasks("Tarefas") }

class MainActivity : ComponentActivity() {
    private val notifications = registerForActivityResult(ActivityResultContracts.RequestPermission()) {}

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        if (Build.VERSION.SDK_INT >= 33) notifications.launch(Manifest.permission.POST_NOTIFICATIONS)
        val repo = MonitorRepository.get(this)
        setContent { MonitorTheme { Root(repo) } }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Root(repo: MonitorRepository) {
    val ui by repo.ui.collectAsStateWithLifecycle()
    // Stream só em primeiro plano; em segundo plano o SyncWorker cuida dos alertas.
    LifecycleEventEffect(Lifecycle.Event.ON_START) { repo.startLive() }
    LifecycleEventEffect(Lifecycle.Event.ON_STOP) { repo.stopLive() }

    val pairing = ui.pairing
    if (pairing == null) {
        Box(Modifier.fillMaxSize().background(Palette.background)) { PairScreen(repo, ui.error) }
        return
    }

    var tab by rememberSaveable { mutableStateOf(Tab.Overview) }
    var cli by rememberSaveable { mutableStateOf<String?>(null) }
    var menu by rememberSaveable { mutableStateOf(false) }
    // Relógio de 1 s para cronômetros e "há x min".
    val now by produceState(Instant.now()) { while (true) { value = Instant.now(); delay(1_000) } }
    val context = androidx.compose.ui.platform.LocalContext.current
    LaunchedEffect(ui.state?.generatedAt) { ui.state?.let { MonitorWidget.update(context, it) } }
    BackHandler(enabled = cli != null) { cli = null }

    Scaffold(
        containerColor = Palette.background,
        topBar = {
            CenterAlignedTopAppBar(
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Palette.background),
                navigationIcon = { if (cli != null) IconButton(onClick = { cli = null }) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Voltar") } },
                title = {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("oDois Monitor", fontWeight = FontWeight.Bold, fontSize = 17.sp)
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Dot(when (ui.connection) { Connection.Live -> Palette.green; Connection.Connecting -> Palette.orange; else -> Palette.red }, 6.dp)
                            HGap(5.dp)
                            Text(
                                when (ui.connection) {
                                    Connection.Live -> pairing.host
                                    Connection.Connecting -> "Conectando a ${pairing.host}…"
                                    else -> "Sem conexão com ${pairing.host}"
                                },
                                color = Palette.secondary, fontSize = 11.sp,
                            )
                        }
                    }
                },
                actions = {
                    IconButton(onClick = { repo.act { it.refresh(); null } }) { Icon(Icons.Rounded.Refresh, "Atualizar") }
                    IconButton(onClick = { menu = true }) { Icon(Icons.Rounded.MoreVert, "Mais") }
                    DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                        DropdownMenuItem(text = { Text("Desparear este celular") }, onClick = { menu = false; repo.unpair() })
                    }
                },
            )
        },
        bottomBar = {
            NavigationBar(containerColor = Palette.surface) {
                Tab.entries.forEach { t ->
                    NavigationBarItem(
                        selected = tab == t && cli == null,
                        onClick = { tab = t; cli = null },
                        icon = {
                            Icon(
                                when (t) { Tab.Overview -> Icons.Rounded.Dashboard; Tab.Clis -> Icons.Rounded.Terminal; Tab.System -> Icons.Rounded.Memory; Tab.Tasks -> Icons.Rounded.Timer },
                                null,
                            )
                        },
                        label = { Text(t.label) },
                        colors = NavigationBarItemDefaults.colors(indicatorColor = Palette.teal.copy(alpha = 0.25f)),
                    )
                }
            }
        },
    ) { padding ->
        PullToRefreshBox(
            isRefreshing = false,
            onRefresh = { repo.act { it.refresh(); null } },
            modifier = Modifier.padding(padding).fillMaxSize(),
        ) {
            val state = ui.state
            Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                ui.error?.takeIf { ui.connection != Connection.Live }?.let { Text(it, color = Palette.orange, fontSize = 13.sp) }
                if (state == null) {
                    Box(Modifier.fillMaxWidth().padding(top = 80.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                } else {
                    val provider = cli?.let { id -> state.providers.firstOrNull { it.id == id } }
                    when {
                        provider != null -> CliDetailScreen(provider, now)
                        tab == Tab.Overview -> OverviewScreen(state, now, ui.receivedAt, openCli = { cli = it }, openTasks = { tab = Tab.Tasks }, openSystem = { tab = Tab.System })
                        tab == Tab.Clis -> CliListScreen(state.providers) { cli = it }
                        tab == Tab.System -> SystemScreen(state) { p, force -> repo.act(if (force) "Processo ${p.pid} encerrado" else "Pedido de parada enviado a ${p.pid}") { it.stopProcess(p.pid, force) } }
                        else -> state.sea?.let { TasksScreen(it, now, ui.receivedAt, repo) }
                            ?: Text("A CLI sea não está configurada no Mac.", color = Palette.secondary)
                    }
                }
                Box(Modifier.padding(bottom = 24.dp))
            }
            ui.toast?.let { msg ->
                Box(Modifier.fillMaxSize().padding(16.dp), contentAlignment = Alignment.BottomCenter) {
                    Text(
                        msg, color = Palette.text, fontWeight = FontWeight.SemiBold,
                        modifier = Modifier
                            .background(Palette.surfaceHigh, androidx.compose.foundation.shape.RoundedCornerShape(14.dp))
                            .padding(horizontal = 16.dp, vertical = 12.dp),
                    )
                }
            }
        }
    }
}
