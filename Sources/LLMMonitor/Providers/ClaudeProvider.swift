import AppKit

/// Claude Code: `~/.claude/projects/<projeto>/<sessão>.jsonl`, uma linha por mensagem,
/// com `message.usage` nas respostas do assistente.
final class ClaudeProvider: UsageProvider, @unchecked Sendable {
    let id = "claude"
    let name = "Claude Code"
    let symbol = "asterisk"
    let tint = NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1)
    let binary = "claude"
    let appBundleNames = ["Claude"]
    var dataDirectory: URL { home.appendingPathComponent(".claude") }

    private let cache = JSONLCache()

    func load() -> UsageSnapshot {
        let root = dataDirectory.appendingPathComponent("projects")
        let files = JSONLCache.recentFiles(under: root, ext: "jsonl")
        let events = cache.events(for: files, parse: Self.parse).deduplicated()

        var snap = Aggregator.snapshot(from: events)
        if let block = Aggregator.activeBlock(events: events) {
            snap.blockTokens = block.tokens
            snap.blockEndsAt = block.endsAt
        }
        if events.isEmpty { snap.note = "Nenhuma resposta registrada nos últimos 7 dias." }
        return snap
    }

    private static func parse(_ url: URL) -> [UsageEvent] {
        var events: [UsageEvent] = []
        let session = url.deletingPathExtension().lastPathComponent
        JSONLCache.forEachObject(in: url, containing: "\"usage\"") { obj in
            guard obj["type"] as? String == "assistant",
                  let message = obj["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any],
                  let date = ISODate.parse(obj["timestamp"]) else { return }
            let model = message["model"] as? String
            if model == "<synthetic>" { return }
            let details = usage["output_tokens_details"] as? [String: Any]
            let tokens = TokenTotals(
                input: int(usage["input_tokens"]),
                output: int(usage["output_tokens"]),
                cacheRead: int(usage["cache_read_input_tokens"]),
                cacheWrite: int(usage["cache_creation_input_tokens"]),
                reasoning: int(details?["thinking_tokens"])
            )
            let key = [message["id"] as? String, obj["requestId"] as? String]
                .compactMap { $0 }.joined(separator: ":")
            events.append(UsageEvent(
                date: date, model: model, session: session, tokens: tokens,
                key: key.isEmpty ? nil : key,
                project: (obj["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
            ))
        }
        return events
    }
}
