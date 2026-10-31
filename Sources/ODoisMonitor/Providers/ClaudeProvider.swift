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

    private let log = IncrementalLog(name: "claude") { ClaudeLineParser(url: $0) }

    func flush() { log.flush() }

    func load() -> UsageSnapshot {
        let root = dataDirectory.appendingPathComponent("projects")
        let files = JSONLCache.recentFiles(under: root, ext: "jsonl")
        let events = log.update(files).flatMap(\.events).deduplicated()

        var snap = Aggregator.snapshot(from: events)
        if let block = Aggregator.activeBlock(events: events) {
            snap.blockTokens = block.tokens
            snap.blockEndsAt = block.endsAt
        }
        snap.account = Accounts.claude()
        if events.isEmpty { snap.note = "Nenhuma resposta registrada nos últimos 7 dias." }
        return snap
    }
}

/// Uma linha por mensagem; só as respostas do assistente têm `message.usage`.
/// Lê os campos direto dos bytes: as linhas podem ter MBs de saída de ferramentas.
final class ClaudeLineParser: LineParser, Codable {
    private enum P {
        static let assistant = JSONBytes.pattern(#""type":"assistant""#)
        static let usage = JSONBytes.pattern(#""usage":{"#)
        static let timestamp = JSONBytes.pattern(#""timestamp":""#)
        static let model = JSONBytes.pattern(#""model":""#)
        static let messageId = JSONBytes.pattern(#""id":"msg_"#)
        static let requestId = JSONBytes.pattern(#""requestId":""#)
        static let cwd = JSONBytes.pattern(#""cwd":""#)
    }

    private let session: String
    private var project: String?

    init(url: URL) {
        session = url.deletingPathExtension().lastPathComponent
    }

    func consume(_ line: Data) -> [UsageEvent] {
        if project == nil, let cwd = JSONBytes.string(in: line, after: P.cwd) {
            project = URL(fileURLWithPath: cwd).lastPathComponent
        }
        guard JSONBytes.contains(line, P.assistant),
              let usage = JSONBytes.object(in: line, after: P.usage),
              let date = FastISO.parse(JSONBytes.string(in: line, after: P.timestamp)) else { return [] }
        let model = JSONBytes.string(in: line, after: P.model)
        if model == "<synthetic>" { return [] }

        let details = usage["output_tokens_details"] as? [String: Any]
        let tokens = TokenTotals(
            input: int(usage["input_tokens"]),
            output: int(usage["output_tokens"]),
            cacheRead: int(usage["cache_read_input_tokens"]),
            cacheWrite: int(usage["cache_creation_input_tokens"]),
            reasoning: int(details?["thinking_tokens"])
        )
        let key = [
            JSONBytes.string(in: line, after: P.messageId).map { "msg_" + $0 },
            JSONBytes.string(in: line, after: P.requestId),
        ].compactMap { $0 }.joined(separator: ":")
        return [UsageEvent(
            date: date, model: model, session: session, tokens: tokens,
            key: key.isEmpty ? nil : key, project: project
        )]
    }
}
