import AppKit

/// Codex CLI: `~/.codex/sessions/AAAA/MM/DD/rollout-*.jsonl`. Os eventos `token_count`
/// trazem o total acumulado da sessão e os limites de uso (`rate_limits`).
final class CodexProvider: UsageProvider, @unchecked Sendable {
    let id = "codex"
    let name = "Codex"
    let symbol = "chevron.left.forwardslash.chevron.right"
    let tint = NSColor(red: 0.42, green: 0.45, blue: 0.98, alpha: 1)
    let binary = "codex"
    let appBundleNames = ["Codex", "ChatGPT"]
    var dataDirectory: URL { home.appendingPathComponent(".codex") }

    private let log = IncrementalLog(name: "codex") { CodexLineParser(url: $0) }

    func flush() { log.flush() }

    func load() -> UsageSnapshot {
        let root = dataDirectory.appendingPathComponent("sessions")
        let files = JSONLCache.recentFiles(under: root, ext: "jsonl")
        let states = log.update(files)
        let events = states.flatMap(\.events).deduplicated()

        var snap = Aggregator.snapshot(from: events)
        if let latest = states.compactMap(\.parser.limits).max(by: { $0.date < $1.date }) {
            snap.limits = latest.limits
            snap.plan = latest.plan
        }
        snap.account = Accounts.codex()
        if events.isEmpty { snap.note = "Nenhuma sessão nos últimos 7 dias." }
        return snap
    }
}

/// Estado de um arquivo de sessão do Codex entre leituras.
final class CodexLineParser: LineParser, Codable {
    struct LimitsInfo: Codable { let date: Date; let limits: [RateLimit]; let plan: String? }

    private enum P {
        static let tokenCount = JSONBytes.pattern(#""type":"token_count""#)
        static let turnContext = JSONBytes.pattern(#""type":"turn_context""#)
        static let sessionMeta = JSONBytes.pattern(#""type":"session_meta""#)
        static let model = JSONBytes.pattern(#""model":""#)
        static let cwd = JSONBytes.pattern(#""cwd":""#)
    }

    private(set) var limits: LimitsInfo?
    private let session: String
    private var model: String?
    private var project: String?
    private var previous: [String: Int]?

    init(url: URL) {
        session = url.deletingPathExtension().lastPathComponent
    }

    func consume(_ line: Data) -> [UsageEvent] {
        // As linhas de conteúdo (mensagens, saídas de ferramentas) são ignoradas sem parse.
        if JSONBytes.contains(line, P.turnContext) {
            model = JSONBytes.string(in: line, after: P.model) ?? model
            return []
        }
        if JSONBytes.contains(line, P.sessionMeta) {
            if project == nil, let cwd = JSONBytes.string(in: line, after: P.cwd) {
                project = URL(fileURLWithPath: cwd).lastPathComponent
            }
            return []
        }
        guard JSONBytes.contains(line, P.tokenCount),
              let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let payload = obj["payload"] as? [String: Any],
              let date = FastISO.parse(obj["timestamp"] as? String) else { return [] }

        if let rl = payload["rate_limits"] as? [String: Any] {
            limits = LimitsInfo(date: date, limits: Self.parseLimits(rl), plan: rl["plan_type"] as? String)
        }
        guard let info = payload["info"] as? [String: Any],
              let totalRaw = info["total_token_usage"] as? [String: Any] else { return [] }
        let total = totalRaw.mapValues { int($0) }

        // Usa a diferença do acumulado: eventos repetidos não contam duas vezes.
        let usage: [String: Any]
        if let prev = previous, total["total_tokens", default: 0] >= prev["total_tokens", default: 0] {
            if total["total_tokens"] == prev["total_tokens"] { return [] }
            usage = total.reduce(into: [:]) { $0[$1.key] = $1.value - prev[$1.key, default: 0] }
        } else if let last = info["last_token_usage"] as? [String: Any] {
            // Primeiro evento do arquivo (sessão retomada traz o acumulado anterior)
            // ou contador zerado: conta só o último turno.
            usage = last
        } else {
            usage = totalRaw
        }
        previous = total

        let cached = int(usage["cached_input_tokens"])
        let tokens = TokenTotals(
            input: max(0, int(usage["input_tokens"]) - cached),
            output: int(usage["output_tokens"]),
            cacheRead: cached,
            cacheWrite: int(usage["cache_write_input_tokens"]),
            reasoning: int(usage["reasoning_output_tokens"])
        )
        let key = "\(obj["timestamp"] ?? ""):\(total["total_tokens", default: 0])"
        return [UsageEvent(date: date, model: model, session: session, tokens: tokens, key: key, project: project)]
    }

    private static func parseLimits(_ rl: [String: Any]) -> [RateLimit] {
        ["primary", "secondary"].compactMap { slot in
            guard let w = rl[slot] as? [String: Any] else { return nil }
            let minutes = int(w["window_minutes"])
            let label: String
            switch minutes {
            case 300: label = "Limite de 5 h"
            case 10_080: label = "Limite semanal"
            case 0: label = slot == "primary" ? "Limite principal" : "Limite secundário"
            default: label = minutes % 1440 == 0 ? "Limite de \(minutes / 1440) d" : "Limite de \(minutes / 60) h"
            }
            let resets = (w["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            return RateLimit(label: label, usedPercent: (w["used_percent"] as? NSNumber)?.doubleValue ?? 0, resetsAt: resets)
        }
    }
}
