package me.o2d.odoismonitor

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import me.o2d.odoismonitor.work.SyncWorker
import java.util.concurrent.TimeUnit

class MonitorApp : Application() {
    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(SyncWorker.CHANNEL_ALERTS, "Alertas do Mac", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "Limites das CLIs, sessão consumindo rápido e memória crítica"
        })
        manager.createNotificationChannel(NotificationChannel(SyncWorker.CHANNEL_DASHBOARD, "Sea Dashboard", NotificationManager.IMPORTANCE_DEFAULT).apply {
            description = "Notificações novas do Dashboard"
        })
        // A cada 15 min (o mínimo do Android) com rede: alertas e widget atualizados.
        WorkManager.getInstance(this).enqueueUniquePeriodicWork(
            "sync",
            ExistingPeriodicWorkPolicy.KEEP,
            PeriodicWorkRequestBuilder<SyncWorker>(15, TimeUnit.MINUTES)
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .build(),
        )
    }
}
