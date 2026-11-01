package me.o2d.odoismonitor

import android.content.Context
import android.content.Intent
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import me.o2d.odoismonitor.data.MonitorState

/**
 * Atalhos do ícone do app (tocar e segurar): pausar o cronômetro em andamento e
 * iniciar as tarefas "em andamento" mais recentes, sem abrir as telas.
 */
object Shortcuts {
    const val ACTION_START = "me.o2d.odoismonitor.START_TASK"
    const val ACTION_PAUSE = "me.o2d.odoismonitor.PAUSE_TIMER"
    const val EXTRA_ID = "id"

    fun update(context: Context, state: MonitorState) {
        val sea = state.sea ?: return ShortcutManagerCompat.removeAllDynamicShortcuts(context)
        val icon = IconCompat.createWithResource(context, R.mipmap.ic_launcher)
        val max = ShortcutManagerCompat.getMaxShortcutCountPerActivity(context).coerceAtMost(4)
        val list = mutableListOf<ShortcutInfoCompat>()

        sea.running?.let { t ->
            list += ShortcutInfoCompat.Builder(context, "pause")
                .setShortLabel("Pausar #${t.task.number}")
                .setLongLabel("Pausar ${t.task.title}")
                .setIcon(icon)
                .setIntent(intent(context, ACTION_PAUSE, t.task.id))
                .build()
        }
        val running = sea.timers.map { it.task.id }.toSet()
        sea.tasks.filter { it.inProgress && it.id !in running }.take(max - list.size).forEach { task ->
            list += ShortcutInfoCompat.Builder(context, "start-${task.id}")
                .setShortLabel("▶ #${task.number}")
                .setLongLabel("Iniciar ${task.title}".take(25))
                .setIcon(icon)
                .setIntent(intent(context, ACTION_START, task.id))
                .build()
        }
        ShortcutManagerCompat.setDynamicShortcuts(context, list)
    }

    private fun intent(context: Context, action: String, id: Int) =
        Intent(context, MainActivity::class.java).setAction(action).putExtra(EXTRA_ID, id)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
}
