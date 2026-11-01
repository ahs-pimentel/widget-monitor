package me.o2d.odoismonitor

import me.o2d.odoismonitor.data.MonitorClient
import me.o2d.odoismonitor.data.MonitorState
import me.o2d.odoismonitor.data.PairingStore
import me.o2d.odoismonitor.data.toInstantOrNull
import me.o2d.odoismonitor.ui.Fmt
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.time.Instant

/** O app entende o JSON que o Mac envia (`GET /v1/state`, contrato v1). */
class ContractTest {
    private fun decode(text: String): MonitorState = MonitorClient.json.decodeFromString(MonitorState.serializer(), text)

    @Test
    fun decodificaFixtureDoContratoV1() {
        val state = decode(javaClass.getResource("/state-v1.json")!!.readText())
        assertEquals(1, state.version)
        assertEquals(listOf("claude", "codex", "gemini", "antigravity", "dk"), state.providers.map { it.id })
        assertTrue(state.providers.all { it.daily.size == 7 })
        assertNotNull(state.generatedAt.toInstantOrNull())
        assertTrue(state.system.ramFraction in 0f..1f)
        val sea = assertNotNullAndGet(state.sea)
        assertEquals(4, sea.tasks.size)
        val timer = assertNotNullAndGet(sea.running)
        // O cronômetro continua contando a partir do estado recebido.
        val received = Instant.parse("2026-10-31T21:00:00Z")
        assertEquals(4810.25, timer.elapsedAt(received.plusSeconds(10), received), 0.001)
        assertEquals(3320.0094, assertNotNullAndGet(sea.ranking).score, 0.0001)
        assertNull(sea.ranking?.position)
    }

    /** Roda contra o JSON real do Mac quando ODOIS_STATE_JSON aponta para ele (fora do repositório). */
    @Test
    fun decodificaEstadoRealQuandoDisponivel() {
        val path = System.getenv("ODOIS_STATE_JSON") ?: return
        val state = decode(File(path).readText())
        assertTrue(state.providers.isNotEmpty())
        println("estado real: ${state.providers.size} CLIs, ${state.processes.size} processos, ${state.sea?.tasks?.size ?: 0} tarefas")
    }

    @Test
    fun pareamentoAceitaSoHttpsETokenLongo() {
        val ok = """{"v":1,"url":"https://monitor.exemplo.com","token":"abcdefghijklmnopqrstuvwxyz012345","host":"Mac"}"""
        assertNotNull(PairingStore.parse(ok))
        assertNull(PairingStore.parse(ok.replace("https://", "http://")))
        assertNull(PairingStore.parse("""{"url":"https://x.com","token":"curto"}"""))
        assertNull(PairingStore.parse("não é json"))
    }

    @Test
    fun formatacaoIgualAoMac() {
        assertEquals("1,2 mil", Fmt.tokens(1_234))
        assertEquals("4,5 M", Fmt.tokens(4_500_000))
        assertEquals("2,1 bi", Fmt.tokens(2_100_000_000))
        assertEquals("1:02:05", Fmt.clock(3725.0))
        assertEquals("2:05", Fmt.clock(125.0))
    }

    private fun <T> assertNotNullAndGet(value: T?): T {
        assertNotNull(value)
        return value!!
    }
}
