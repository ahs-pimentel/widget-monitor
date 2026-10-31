import AppKit

/// DK CLI: `~/.dk/projects/<projeto>/sessions/<sessão>.json`. Cada sessão tem um array
/// `usage` no formato OpenAI/OpenRouter (`prompt_tokens`, `completion_tokens`, `cost`)
/// com `_dk.provider` e `_dk.at`.
///
/// Quando o DK roda os motores nativos (`claude`, `codex`), o consumo já aparece nos
/// logs dessas CLIs; aqui entram só as chamadas diretas (OpenRouter, API da Anthropic…).
final class DKProvider: UsageProvider, @unchecked Sendable {
    let id = "dk"
    let name = "DK"
    let symbol = "square.stack.3d.up.fill"
    let monogram: String? = "DK"
    let tint = NSColor(red: 0.13, green: 0.72, blue: 0.62, alpha: 1)
    let binary = "dk"
    let appBundleNames: [String] = []
    var dataDirectory: URL { home.appendingPathComponent(".dk") }

    /// Motores nativos cujo consumo já é contado pelos providers próprios.
    private static let nativeEngines: Set<String> = ["claude", "codex", "gemini"]

    private let cache = JSONLCache()

    func load() -> UsageSnapshot {
        let root = dataDirectory.appendingPathComponent("projects")
        let files = JSONLCache.recentFiles(under: root, ext: "json")
            .filter { $0.deletingLastPathComponent().lastPathComponent == "sessions" }
        let events = cache.events(for: files, parse: Self.parse)

        var snap = Aggregator.snapshot(from: events)
        // Fonte principal do consumo da semana, para o card dizer "via OpenRouter".
        var bySource: [String: Int] = [:]
        for e in events { bySource[e.key?.components(separatedBy: "|").first ?? "", default: 0] += e.tokens.total }
        if let main = bySource.max(by: { $0.value < $1.value })?.key, !main.isEmpty {
            snap.source = "via \(Self.label(main))"
        }
        if events.isEmpty {
            snap.note = "Nenhuma chamada via OpenRouter ou API direta nos últimos 7 dias."
        }
        return snap
    }

    private static func label(_ provider: String) -> String {
        switch provider {
        case "openrouter": return "OpenRouter"
        case "anthropic": return "API Anthropic"
        case "openai": return "API OpenAI"
        default: return provider
        }
    }

    private static func parse(_ url: URL) -> [UsageEvent] {
        guard let data = try? Data(contentsOf: url),
              let session = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usage = session["usage"] as? [[String: Any]] else { return [] }
        let sessionId = session["id"] as? String ?? url.deletingPathExtension().lastPathComponent
        let fallbackDate = ISODate.parse(session["updated"])

        return usage.enumerated().compactMap { index, u in
            let meta = u["_dk"] as? [String: Any] ?? [:]
            let provider = meta["provider"] as? String ?? session["provider"] as? String ?? ""
            if nativeEngines.contains(provider) { return nil }
            guard let date = ISODate.parse(meta["at"]) ?? fallbackDate else { return nil }

            let prompt = u["prompt_tokens_details"] as? [String: Any]
            let completion = u["completion_tokens_details"] as? [String: Any]
            let cached = int(prompt?["cached_tokens"])
            let cacheWrite = int(prompt?["cache_write_tokens"])
            let tokens = TokenTotals(
                input: max(0, int(u["prompt_tokens"]) - cached - cacheWrite),
                output: int(u["completion_tokens"]),
                cacheRead: cached,
                cacheWrite: cacheWrite,
                reasoning: int(completion?["reasoning_tokens"])
            )
            return UsageEvent(
                date: date,
                model: meta["model"] as? String ?? session["model"] as? String,
                session: sessionId,
                tokens: tokens,
                // A fonte vai na chave para o resumo "via …"; o índice evita colisões.
                key: "\(provider)|\(sessionId)#\(index)",
                cost: (u["cost"] as? NSNumber)?.doubleValue ?? 0,
                project: (session["root"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
            )
        }
    }
}
