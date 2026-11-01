package me.o2d.odoismonitor.data

import kotlinx.serialization.Serializable
import java.time.Instant

/** Contrato v1 do Mac (`RemoteState`). Datas em ISO 8601; frações de 0 a 1. */
@Serializable
data class MonitorState(
    val version: Int = 1,
    val appVersion: String = "",
    val generatedAt: String = "",
    val host: String = "Mac",
    val providers: List<Provider> = emptyList(),
    val system: SystemInfo = SystemInfo(),
    val processes: List<CliProcess> = emptyList(),
    val sea: Sea? = null,
    val activeSessions: Int = 0,
) {
    val todayTotal: Long get() = providers.sumOf { it.today.total }

    /** O limite mais alto entre as CLIs (nome da CLI, limite). */
    val topLimit: Pair<Provider, Limit>?
        get() = providers.flatMap { p -> p.limits.map { p to it } }.maxByOrNull { it.second.usedPercent }
}

@Serializable
data class Provider(
    val id: String,
    val name: String,
    val tint: String = "#888888",
    val symbol: String = "",
    val monogram: String? = null,
    val hasIcon: Boolean = false,
    val account: String? = null,
    val plan: String? = null,
    val source: String? = null,
    val active: Boolean = false,
    val lastActivity: String? = null,
    val today: Tokens = Tokens(),
    val messagesToday: Int = 0,
    val sessionsToday: Int = 0,
    val topModel: String? = null,
    val weekTotal: Long = 0,
    val daily: List<Long> = List(7) { 0L },
    val costToday: Double? = null,
    val costWeek: Double? = null,
    val limits: List<Limit> = emptyList(),
    val block: Block? = null,
    val sessions: List<Session> = emptyList(),
    val note: String? = null,
) {
    val topLimit: Limit? get() = limits.maxByOrNull { it.usedPercent }
}

@Serializable
data class Tokens(
    val total: Long = 0, val input: Long = 0, val output: Long = 0,
    val cacheRead: Long = 0, val cacheWrite: Long = 0, val reasoning: Long = 0,
)

@Serializable
data class Limit(val label: String, val usedPercent: Double, val resetsAt: String? = null) {
    val fraction: Float get() = (usedPercent / 100).coerceIn(0.0, 1.0).toFloat()
}

@Serializable
data class Block(val tokens: Long, val endsAt: String)

@Serializable
data class Session(
    val id: String,
    val project: String? = null,
    val model: String? = null,
    val tokens: Long = 0,
    val messages: Int = 0,
    val cost: Double = 0.0,
    val last: String,
    val active: Boolean = false,
)

@Serializable
data class SystemInfo(
    val cpu: Double = 0.0,
    val ramUsed: Long = 0,
    val ramTotal: Long = 0,
    val swapUsed: Long = 0,
    val swapTotal: Long = 0,
    val pressure: Double = 0.0,
    val pressureLevel: String = "normal",
    val gpu: Double? = null,
    val cpuHistory: List<Double> = emptyList(),
    val pressureHistory: List<Double> = emptyList(),
) {
    val ramFraction: Float get() = if (ramTotal > 0) (ramUsed.toDouble() / ramTotal).toFloat() else 0f
}

@Serializable
data class CliProcess(
    val pid: Int,
    val cli: String,
    val cliName: String,
    val project: String? = null,
    val directory: String? = null,
    val cpu: Double = 0.0,
    val memory: Long = 0,
    val startedAt: String? = null,
    val background: Boolean = false,
    val stopping: Boolean = false,
)

@Serializable
data class Sea(
    val account: String? = null,
    val dashboardURL: String? = null,
    val loading: Boolean = false,
    val error: String? = null,
    val updatedAt: String? = null,
    val tasks: List<SeaTask> = emptyList(),
    val timers: List<TaskTimer> = emptyList(),
    val notifications: List<SeaNotification> = emptyList(),
    val ranking: Ranking? = null,
    val message: String? = null,
) {
    val running: TaskTimer? get() = timers.firstOrNull { it.running }
    val accountName: String? get() = account?.substringBefore(" · ")
}

@Serializable
data class SeaTask(
    val id: Int,
    val number: Int,
    val subject: String,
    val statusId: Int = 2,
    val inProgress: Boolean = false,
    val projectSlug: String,
    val projectName: String,
    val url: String? = null,
    val busy: Boolean = false,
) {
    val title: String get() = "#$number $subject"
}

@Serializable
data class TaskTimer(
    val task: SeaTask,
    val startedAt: String,
    val accumulated: Double = 0.0,
    val runningSince: String? = null,
    val running: Boolean = false,
    val elapsed: Double = 0.0,
    val preferredActivityType: Int? = null,
) {
    /** Segundos agora, contando a partir do estado recebido. */
    fun elapsedAt(now: Instant, receivedAt: Instant): Double =
        if (running) elapsed + (now.toEpochMilli() - receivedAt.toEpochMilli()) / 1000.0 else elapsed
}

@Serializable
data class SeaNotification(
    val id: Int,
    val title: String,
    val body: String = "",
    val actor: String? = null,
    val url: String? = null,
    val createdAt: String? = null,
)

@Serializable
data class Ranking(
    val year: Int,
    val score: Double,
    val manual: Double = 0.0,
    val automatic: Double = 0.0,
    val badges: Double = 0.0,
    val position: Int? = null,
    val total: Int? = null,
)

@Serializable
data class ActivityType(val id: Int, val label: String)

@Serializable
data class ActivityTypes(val data: List<ActivityType> = emptyList(), val preferred: Int? = null)

@Serializable
data class ApiError(val error: ApiErrorBody? = null)

@Serializable
data class ApiErrorBody(val code: String = "", val message: String = "")

/** Conteúdo do QR code gerado no Mac (*Parear celular…*). */
@Serializable
data class PairingInfo(
    val v: Int = 1,
    val url: String,
    val token: String,
    val host: String = "Mac",
    val device: String = "Celular",
)

fun String?.toInstantOrNull(): Instant? = this?.let { runCatching { Instant.parse(it) }.getOrNull() }
