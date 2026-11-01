package me.o2d.odoismonitor.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.sse.EventSource
import okhttp3.sse.EventSourceListener
import okhttp3.sse.EventSources
import java.io.IOException
import java.util.concurrent.TimeUnit

/** Falha da API com a mensagem do Mac (em pt-BR) e o código HTTP. */
class MonitorException(val status: Int, message: String) : IOException(message)

/** Fala com o oDois Monitor do Mac pela API v1 (HTTPS via túnel da Cloudflare). */
class MonitorClient(private val pairing: PairingInfo) {
    private val http = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()
    // SSE: sem tempo limite de leitura (a conexão fica aberta).
    private val streaming = http.newBuilder().readTimeout(0, TimeUnit.SECONDS).build()

    private fun request(path: String) = Request.Builder()
        .url(pairing.url.trimEnd('/') + path)
        .header("Authorization", "Bearer ${pairing.token}")
        .header("User-Agent", "oDois-Monitor-Android")

    private suspend fun execute(req: Request): String = withContext(Dispatchers.IO) {
        http.newCall(req).execute().use { resp -> body(resp) }
    }

    private fun body(resp: Response): String {
        val text = resp.body.string()
        if (!resp.isSuccessful) {
            val message = runCatching { json.decodeFromString(ApiError.serializer(), text).error?.message }.getOrNull()
            throw MonitorException(resp.code, message?.takeIf { it.isNotBlank() } ?: "O Mac respondeu ${resp.code}.")
        }
        return text
    }

    suspend fun hello(): String = execute(request("/v1/hello").build())

    suspend fun state(): MonitorState = json.decodeFromString(MonitorState.serializer(), execute(request("/v1/state").build()))

    /** Estado ao vivo (SSE, a cada ~2 s). Fecha o stream quando o coletor cancela. */
    fun stream(): Flow<MonitorState> = callbackFlow {
        val source = EventSources.createFactory(streaming).newEventSource(
            request("/v1/stream").header("Accept", "text/event-stream").build(),
            object : EventSourceListener() {
                override fun onEvent(eventSource: EventSource, id: String?, type: String?, data: String) {
                    runCatching { json.decodeFromString(MonitorState.serializer(), data) }.onSuccess { trySend(it) }
                }
                override fun onFailure(eventSource: EventSource, t: Throwable?, response: Response?) {
                    val code = response?.code ?: 0
                    close(if (code == 401) MonitorException(401, "Aparelho não pareado ou revogado.") else (t ?: IOException("Conexão perdida")))
                }
                override fun onClosed(eventSource: EventSource) {
                    close(IOException("Stream encerrado"))
                }
            },
        )
        awaitClose { source.cancel() }
    }

    private suspend fun post(path: String, body: JsonObject = JsonObject(emptyMap())): MonitorState {
        val req = request(path).post(body.toString().toRequestBody("application/json".toMediaType())).build()
        return json.decodeFromString(MonitorState.serializer(), execute(req))
    }

    suspend fun refresh() { execute(request("/v1/refresh").post("{}".toRequestBody("application/json".toMediaType())).build()) }
    suspend fun startTask(id: Int) = post("/v1/tasks/$id/start")
    suspend fun pauseTimer(id: Int) = post("/v1/timers/$id/pause")
    suspend fun discardTimer(id: Int) = post("/v1/timers/$id/discard", buildJsonObject { put("confirm", JsonPrimitive(true)) })
    suspend fun finishTimer(id: Int, hours: Double, date: String, activityType: Int, comment: String) =
        post("/v1/timers/$id/finish", buildJsonObject {
            put("hours", JsonPrimitive(hours))
            put("date", JsonPrimitive(date))
            put("activityType", JsonPrimitive(activityType))
            put("comment", JsonPrimitive(comment))
        })
    suspend fun markRead(id: Int) = post("/v1/notifications/$id/read")
    suspend fun stopProcess(pid: Int, force: Boolean) =
        post("/v1/processes/$pid/stop", buildJsonObject {
            put("confirm", JsonPrimitive(true))
            put("force", JsonPrimitive(force))
        })

    suspend fun activityTypes(slug: String): ActivityTypes =
        json.decodeFromString(ActivityTypes.serializer(), execute(request("/v1/projects/$slug/activity-types").build()))

    /** PNG (ícone de CLI ou avatar); null se o Mac não tiver. */
    suspend fun image(path: String): ByteArray? = withContext(Dispatchers.IO) {
        runCatching { http.newCall(request(path).build()).execute().use { if (it.isSuccessful) it.body.bytes() else null } }.getOrNull()
    }

    companion object {
        val json = Json { ignoreUnknownKeys = true; explicitNulls = false; coerceInputValues = true }
    }
}
