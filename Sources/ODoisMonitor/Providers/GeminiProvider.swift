import AppKit

/// Gemini CLI: `~/.gemini/tmp/<projeto>/chats/session-*.jsonl` (formato atual, uma
/// mensagem por linha) ou `session-*.json` (formato antigo, com `messages`).
/// As respostas do tipo `gemini` trazem `tokens` e `model`.
final class GeminiProvider: UsageProvider, @unchecked Sendable {
    let id = "gemini"
    let name = "Gemini CLI"
    let symbol = "sparkle"
    let tint = NSColor(red: 0.27, green: 0.55, blue: 0.98, alpha: 1)
    let binary = "gemini"
    let appBundleNames = ["Gemini"]
    var dataDirectory: URL { home.appendingPathComponent(".gemini") }

    private let cache = JSONLCache()

    func load() -> UsageSnapshot {
        let root = dataDirectory.appendingPathComponent("tmp")
        let files = JSONLCache.recentFiles(under: root, ext: "jsonl")
            + JSONLCache.recentFiles(under: root, ext: "json").filter { $0.lastPathComponent.hasPrefix("session-") }
        let events = cache.events(for: files, parse: Self.parse).deduplicated()

        var snap = Aggregator.snapshot(from: events)
        snap.account = Accounts.gemini()
        if events.isEmpty {
            snap.note = "Os logs locais ainda não têm respostas com contagem de tokens."
        }
        return snap
    }

    private static func parse(_ url: URL) -> [UsageEvent] {
        let session = url.deletingPathExtension().lastPathComponent
        var byId: [String: UsageEvent] = [:]
        var order: [String] = []

        func add(_ msg: [String: Any]) {
            guard msg["type"] as? String == "gemini",
                  let t = msg["tokens"] as? [String: Any],
                  let date = ISODate.parse(msg["timestamp"]) else { return }
            let cached = int(t["cached"])
            let tokens = TokenTotals(
                input: max(0, int(t["input"]) - cached),
                output: int(t["output"]) + int(t["thoughts"]),
                cacheRead: cached,
                reasoning: int(t["thoughts"])
            )
            let id = msg["id"] as? String ?? UUID().uuidString
            if byId[id] == nil { order.append(id) }
            // Atualizações posteriores da mesma mensagem substituem a anterior.
            byId[id] = UsageEvent(
                date: date, model: msg["model"] as? String, session: session, tokens: tokens, key: id,
                project: url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
            )
        }

        if url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let messages = obj["messages"] as? [[String: Any]] else { return [] }
            messages.forEach(add)
        } else {
            JSONLCache.forEachObject(in: url) { obj in
                if let set = obj["$set"] as? [String: Any], let messages = set["messages"] as? [[String: Any]] {
                    messages.forEach(add)
                } else {
                    add(obj)
                }
            }
        }
        return order.compactMap { byId[$0] }
    }
}
