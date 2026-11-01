package me.o2d.odoismonitor.widget

import android.content.Context
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.LinearProgressIndicator
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.state.updateAppWidgetState
import androidx.glance.background
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.state.PreferencesGlanceStateDefinition
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import androidx.datastore.preferences.core.stringPreferencesKey
import me.o2d.odoismonitor.MainActivity
import me.o2d.odoismonitor.data.MonitorClient
import me.o2d.odoismonitor.data.MonitorState
import me.o2d.odoismonitor.ui.Fmt
import java.time.Instant

/** Widget da tela inicial: tokens de hoje, o limite mais alto e o cronômetro em andamento. */
class MonitorWidget : GlanceAppWidget() {
    override val stateDefinition = PreferencesGlanceStateDefinition

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            val json = currentState(KEY)
            val state = json?.let { runCatching { MonitorClient.json.decodeFromString(MonitorState.serializer(), it) }.getOrNull() }
            val white = ColorProvider(Color.White)
            val grey = ColorProvider(Color(0xFF9A9AAE))
            Column(
                GlanceModifier.fillMaxSize().background(Color(0xFF15151F)).cornerRadius(22.dp).padding(14.dp)
                    .clickable(actionStartActivity<MainActivity>()),
            ) {
                Text("oDois Monitor${state?.let { " · ${it.host}" } ?: ""}", style = TextStyle(color = grey, fontSize = 11.sp))
                if (state == null) {
                    Text("Abra o app para parear", style = TextStyle(color = white, fontSize = 14.sp))
                    return@Column
                }
                Row(verticalAlignment = Alignment.Bottom) {
                    Text(Fmt.tokens(state.todayTotal), style = TextStyle(color = white, fontSize = 26.sp, fontWeight = FontWeight.Bold))
                    Text("  tokens hoje", style = TextStyle(color = grey, fontSize = 12.sp))
                }
                state.topLimit?.let { (p, l) ->
                    Spacer(GlanceModifier.height(6.dp))
                    val c = when { l.usedPercent >= 90 -> Color(0xFFFF453A); l.usedPercent >= 70 -> Color(0xFFFF9F0A); else -> Color(0xFF34C759) }
                    Text("${p.name} · ${l.label.lowercase()} ${l.usedPercent.toInt()}%", style = TextStyle(color = ColorProvider(c), fontSize = 12.sp, fontWeight = FontWeight.Bold))
                    LinearProgressIndicator(l.fraction, GlanceModifier.fillMaxWidth().height(5.dp), color = ColorProvider(c), backgroundColor = ColorProvider(Color(0x33FFFFFF)))
                }
                state.sea?.running?.let { t ->
                    Spacer(GlanceModifier.height(8.dp))
                    val generated = runCatching { Instant.parse(state.generatedAt) }.getOrDefault(Instant.now())
                    Row(GlanceModifier.fillMaxWidth().background(Color(0xFF544CEB)).cornerRadius(12.dp).padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text("⏱ ${Fmt.clock(t.elapsedAt(Instant.now(), generated))}", style = TextStyle(color = white, fontSize = 15.sp, fontWeight = FontWeight.Bold))
                        Text("  ${t.task.title}", style = TextStyle(color = white, fontSize = 11.sp), maxLines = 1)
                    }
                }
            }
        }
    }

    companion object {
        val KEY = stringPreferencesKey("state")

        /** Guarda o estado mais recente e redesenha os widgets. */
        suspend fun update(context: Context, state: MonitorState) {
            val manager = GlanceAppWidgetManager(context)
            val json = MonitorClient.json.encodeToString(MonitorState.serializer(), state)
            manager.getGlanceIds(MonitorWidget::class.java).forEach { id ->
                updateAppWidgetState(context, id) { it[KEY] = json }
                MonitorWidget().update(context, id)
            }
        }
    }
}

class MonitorWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = MonitorWidget()
}
