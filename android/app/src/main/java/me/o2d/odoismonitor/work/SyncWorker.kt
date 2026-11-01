package me.o2d.odoismonitor.work

import android.Manifest
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import me.o2d.odoismonitor.MainActivity
import me.o2d.odoismonitor.R
import me.o2d.odoismonitor.data.MonitorClient
import me.o2d.odoismonitor.data.MonitorState
import me.o2d.odoismonitor.data.PairingStore
import me.o2d.odoismonitor.widget.MonitorWidget

/** Em segundo plano: busca o estado do Mac, avisa o que é novo e atualiza o widget. */
class SyncWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val pairing = PairingStore(applicationContext).load() ?: return Result.success()
        val state = runCatching { MonitorClient(pairing).state() }.getOrElse { return Result.retry() }
        MonitorWidget.update(applicationContext, state)
        notify(applicationContext, state)
        return Result.success()
    }

    companion object {
        const val CHANNEL_ALERTS = "alerts"
        const val CHANNEL_DASHBOARD = "dashboard"

        /** Mesmas regras do Mac; cada caso avisa uma vez (chave guardada). */
        fun notify(context: Context, state: MonitorState) {
            if (ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
            val prefs = context.getSharedPreferences("alerts", Context.MODE_PRIVATE)
            val sent = prefs.getStringSet("sent", emptySet()).orEmpty().toMutableSet()
            val first = !prefs.getBoolean("seeded", false)

            fun post(key: String, channel: String, title: String, body: String) {
                if (!sent.add(key) || first) return
                val intent = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
                val n = NotificationCompat.Builder(context, channel)
                    .setSmallIcon(R.mipmap.ic_launcher)
                    .setContentTitle(title)
                    .setContentText(body)
                    .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                    .setContentIntent(intent)
                    .setAutoCancel(true)
                    .build()
                NotificationManagerCompat.from(context).notify(key.hashCode(), n)
            }

            state.providers.forEach { p ->
                p.limits.forEach { l ->
                    val level = when { l.usedPercent >= 100 -> 100; l.usedPercent >= 90 -> 90; else -> null }
                    if (level != null) {
                        post(
                            "limit:${p.id}:${l.label}:${l.resetsAt}:$level", CHANNEL_ALERTS,
                            if (level >= 100) "${p.name}: ${l.label.lowercase()} esgotado" else "${p.name}: ${l.label.lowercase()} em ${l.usedPercent.toInt()}%",
                            "No Mac ${state.host}.",
                        )
                    }
                }
            }
            if (state.system.pressureLevel == "critical") {
                post("memory:${System.currentTimeMillis() / 1_800_000}", CHANNEL_ALERTS, "Pressão de memória crítica", "O Mac ${state.host} está sem memória livre.")
            }
            state.sea?.notifications?.forEach { n ->
                post("sea:${n.id}", CHANNEL_DASHBOARD, n.title, n.body)
            }
            // Na primeira vez só registra o que já existe (não dispara uma enxurrada).
            prefs.edit().putStringSet("sent", sent.toList().takeLast(400).toSet()).putBoolean("seeded", true).apply()
        }
    }
}
