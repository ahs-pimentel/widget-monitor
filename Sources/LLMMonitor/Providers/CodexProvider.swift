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

    private struct LimitsInfo { let date: Date; let limits: [RateLimit]; let plan: String? }
    private struct FileResult { let events: [UsageEvent]; let limits: LimitsInfo? }

    private let cache = JSONLCache()
    private var limitsByFile: [String: LimitsInfo] = [:]
    private let lock = NSLock()

    func load() -> UsageSnapshot {
        let root = dataDirectory.appendingPathComponent("sessions")
        let files = JSONLCache.recentFiles(under: root, ext: "jsonl")
        let events = cache.events(for: files) { url in
            let result = Self.parse(url)
            lock.lock()
            limitsByFile[url.path] = result.limits
            lock.unlock()
            return result.events
        }.deduplicated()

        var snap = Aggregator.snapshot(from: events)
        lock.lock()
        let latest = files.compactMap { limitsByFile[$0.path] }.max { $0.date < $1.date }
        lock.unlock()
        if let latest {
            snap.limits = latest.limits
            snap.plan = latest.plan
        }
        if events.isEmpty { snap.note = "Nenhuma sessão nos últimos 7 dias." }
        return snap
    }

    private static func parse(_ url: URL) -> FileResult {
        var events: [UsageEvent] = []
        var limits: LimitsInfo?
        var model: String?
        var project: String?
        var previous: [String: Any]?
        let session = url.deletingPathExtension().lastPathComponent

        JSONLCache.forEachObject(in: url) { obj in
            guard let payload = obj["payload"] as? [String: Any] else { return }
            if obj["type"] as? String == "session_meta", project == nil, let cwd = payload["cwd"] as? String {
                project = URL(fileURLWithPath: cwd).lastPathComponent
                return
            }
            if obj["type"] as? String == "turn_context" {
                model = payload["model"] as? String ?? model
                return
            }
            guard obj["type"] as? String == "event_msg",
                  payload["type"] as? String == "token_count",
                  let date = ISODate.parse(obj["timestamp"]) else { return }

            if let rl = payload["rate_limits"] as? [String: Any] {
                limits = LimitsInfo(date: date, limits: parseLimits(rl), plan: rl["plan_type"] as? String)
            }
            guard let info = payload["info"] as? [String: Any],
                  let total = info["total_token_usage"] as? [String: Any] else { return }

            // Usa a diferença do acumulado: eventos repetidos não contam duas vezes.
            let usage: [String: Any]
            if let prev = previous, int(total["total_tokens"]) >= int(prev["total_tokens"]) {
                if int(total["total_tokens"]) == int(prev["total_tokens"]) { return }
                usage = total.reduce(into: [:]) { $0[$1.key] = int($1.value) - int(prev[$1.key]) }
            } else if let last = info["last_token_usage"] as? [String: Any] {
                // Primeiro evento do arquivo (sessão retomada traz o acumulado anterior)
                // ou contador zerado: conta só o último turno.
                usage = last
            } else {
                usage = total
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
            let key = "\(obj["timestamp"] ?? ""):\(int(total["total_tokens"]))"
            events.append(UsageEvent(date: date, model: model, session: session, tokens: tokens, key: key, project: project))
        }
        return FileResult(events: events, limits: limits)
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
