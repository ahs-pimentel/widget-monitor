package me.o2d.odoismonitor.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.time.Instant

enum class Connection { Unpaired, Connecting, Live, Offline }

data class UiState(
    val pairing: PairingInfo? = null,
    val connection: Connection = Connection.Unpaired,
    val state: MonitorState? = null,
    /** Quando o último estado chegou (o cronômetro conta a partir daqui). */
    val receivedAt: Instant = Instant.now(),
    val error: String? = null,
    /** Mensagem curta de resultado de uma ação ("Horas registradas"). */
    val toast: String? = null,
)

/** Estado do monitor para o app inteiro: stream ao vivo com reconexão e ações. */
class MonitorRepository private constructor(context: Context) {
    private val store = PairingStore(context)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val _ui = MutableStateFlow(UiState(pairing = store.load()))
    val ui: StateFlow<UiState> = _ui.asStateFlow()
    private var liveJob: Job? = null
    private val images = mutableMapOf<String, Bitmap?>()

    val client: MonitorClient? get() = _ui.value.pairing?.let(::MonitorClient)

    init {
        if (_ui.value.pairing != null) _ui.update { it.copy(connection = Connection.Connecting) }
    }

    /** Pareia com o conteúdo do QR code e confere com `/v1/hello`. */
    suspend fun pair(raw: String): String? {
        val info = PairingStore.parse(raw) ?: return "Código inválido. Gere um novo em Acesso remoto → Parear celular… no Mac."
        return runCatching { MonitorClient(info).hello() }.fold(
            onSuccess = {
                store.save(info)
                _ui.update { UiState(pairing = info, connection = Connection.Connecting) }
                startLive()
                null
            },
            onFailure = { it.message ?: "Não consegui falar com o Mac." },
        )
    }

    fun unpair() {
        stopLive()
        store.clear()
        images.clear()
        _ui.value = UiState()
    }

    /** Liga o stream (app em primeiro plano). Reconecta com espera crescente. */
    fun startLive() {
        val client = client ?: return
        if (liveJob?.isActive == true) return
        liveJob = scope.launch {
            var backoff = 2_000L
            while (isActive) {
                try {
                    if (_ui.value.state == null) apply(client.state())
                    client.stream().collect {
                        backoff = 2_000L
                        apply(it)
                    }
                } catch (e: MonitorException) {
                    if (e.status == 401) {
                        _ui.update { it.copy(connection = Connection.Offline, error = "Este celular foi desconectado no Mac. Pareie de novo.") }
                        return@launch
                    }
                    _ui.update { it.copy(connection = Connection.Offline, error = e.message) }
                } catch (e: Exception) {
                    _ui.update { it.copy(connection = Connection.Offline, error = "Sem conexão com o Mac (${e.message ?: "rede"}).") }
                }
                delay(backoff)
                backoff = (backoff * 2).coerceAtMost(30_000L)
                _ui.update { it.copy(connection = Connection.Connecting) }
            }
        }
    }

    fun stopLive() {
        liveJob?.cancel()
        liveJob = null
    }

    private fun apply(state: MonitorState) {
        _ui.update { it.copy(state = state, receivedAt = Instant.now(), connection = Connection.Live, error = null) }
    }

    /** Executa uma ação; o Mac devolve o estado novo. Falhas viram toast. */
    fun act(success: String? = null, block: suspend (MonitorClient) -> MonitorState?) {
        val client = client ?: return
        scope.launch {
            runCatching { block(client) }
                .onSuccess { state ->
                    state?.let(::apply)
                    if (success != null) toast(success)
                }
                .onFailure { toast(it.message ?: "Falhou.") }
        }
    }

    fun toast(text: String) {
        _ui.update { it.copy(toast = text) }
        scope.launch {
            delay(3_500)
            _ui.update { if (it.toast == text) it.copy(toast = null) else it }
        }
    }

    suspend fun image(path: String): Bitmap? {
        if (images.containsKey(path)) return images[path]
        val bytes = client?.image(path)
        val bitmap = bytes?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
        images[path] = bitmap
        return bitmap
    }

    companion object {
        @Volatile private var instance: MonitorRepository? = null
        fun get(context: Context): MonitorRepository =
            instance ?: synchronized(this) { instance ?: MonitorRepository(context.applicationContext).also { instance = it } }
    }
}
