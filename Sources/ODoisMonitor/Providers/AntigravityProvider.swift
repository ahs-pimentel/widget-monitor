import AppKit
import SQLite3

/// Antigravity CLI (`agy`): `~/.gemini/antigravity-cli/conversations/<id>.db`, um SQLite por
/// conversa. Cada geração grava um passo (`steps`) cujo `metadata` é um protobuf com:
/// `1` = horário (Timestamp) e `9` = uso (`2` entrada, `3` saída, `5` cache lido, `6` raciocínio).
/// O modelo vem do `gen_metadata` (`1.19`) e a pasta do projeto, de `conversation_summaries.db`.
/// Formato levantado nos arquivos (não há documentação pública); campos ausentes viram zero.
final class AntigravityProvider: UsageProvider, @unchecked Sendable {
    let id = "antigravity"
    let name = "Antigravity"
    let symbol = "arrow.up.circle"
    let tint = NSColor(red: 0.20, green: 0.45, blue: 0.95, alpha: 1)
    let binary = "agy"
    let appBundleNames = ["Antigravity"]
    var dataDirectory: URL { home.appendingPathComponent(".gemini/antigravity-cli") }

    private struct Entry { let stamp: Date; let events: [UsageEvent] }
    private var cache: [String: Entry] = [:]
    private let lock = NSLock()

    func load() -> UsageSnapshot {
        let dir = dataDirectory.appendingPathComponent("conversations")
        let files = JSONLCache.recentFiles(under: dir, ext: "db")
        let projects = Self.projects(dataDirectory.appendingPathComponent("conversation_summaries.db"))

        var events: [UsageEvent] = []
        lock.lock()
        var next: [String: Entry] = [:]
        for url in files {
            let stamp = Self.modified(url)
            if let hit = cache[url.path], hit.stamp == stamp {
                next[url.path] = hit
            } else {
                let session = url.deletingPathExtension().lastPathComponent
                next[url.path] = Entry(stamp: stamp, events: Self.parse(url, session: session, project: projects[session]))
            }
            events += next[url.path]?.events ?? []
        }
        cache = next
        lock.unlock()
        return Aggregator.snapshot(from: events)
    }

    /// Data de modificação do banco ou do WAL, o que for mais novo (o WAL muda antes do .db).
    private static func modified(_ url: URL) -> Date {
        let wal = URL(fileURLWithPath: url.path + "-wal")
        return [url, wal].compactMap {
            try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }.max() ?? .distantPast
    }

    private static func parse(_ url: URL, session: String, project: String?) -> [UsageEvent] {
        guard let db = SQLiteReader(url) else { return [] }
        let model = db.blobs("SELECT data FROM gen_metadata ORDER BY idx DESC LIMIT 5")
            .lazy.compactMap { Proto($0).message(1)?.string(19) }.first
        var events: [UsageEvent] = []
        for (idx, blob) in db.indexedBlobs("SELECT idx, metadata FROM steps WHERE metadata IS NOT NULL") {
            let meta = Proto(blob)
            guard let usage = meta.message(9), let seconds = meta.message(1)?.int(1), seconds > 0 else { continue }
            let tokens = TokenTotals(
                input: usage.int(2), output: usage.int(3), cacheRead: usage.int(5), cacheWrite: 0, reasoning: usage.int(6)
            )
            guard tokens.total > 0 else { continue }
            events.append(UsageEvent(
                date: Date(timeIntervalSince1970: TimeInterval(seconds)), model: model, session: session,
                tokens: tokens, key: "\(session):\(idx)", project: project
            ))
        }
        return events
    }

    /// Pasta do projeto de cada conversa (primeiro workspace).
    private static func projects(_ url: URL) -> [String: String] {
        guard let db = SQLiteReader(url) else { return [:] }
        var result: [String: String] = [:]
        for (id, uris) in db.texts("SELECT conversation_id, workspace_uris FROM conversation_summaries") {
            guard let data = uris.data(using: .utf8),
                  let list = try? JSONSerialization.jsonObject(with: data) as? [String],
                  let first = list.first, let path = URL(string: first)?.path, !path.isEmpty else { continue }
            result[id] = (path as NSString).lastPathComponent
        }
        return result
    }
}

/// Leitura somente-leitura de um SQLite (a CLI pode estar escrevendo ao mesmo tempo).
private final class SQLiteReader {
    private var db: OpaquePointer?

    init?(_ url: URL) {
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        sqlite3_busy_timeout(db, 200)
    }

    deinit { sqlite3_close(db) }

    private func each(_ sql: String, _ row: (OpaquePointer) -> Void) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW { row(stmt) }
    }

    private static func blob(_ stmt: OpaquePointer, _ col: Int32) -> Data {
        guard let p = sqlite3_column_blob(stmt, col) else { return Data() }
        return Data(bytes: p, count: Int(sqlite3_column_bytes(stmt, col)))
    }

    private static func text(_ stmt: OpaquePointer, _ col: Int32) -> String {
        sqlite3_column_text(stmt, col).map { String(cString: $0) } ?? ""
    }

    func blobs(_ sql: String) -> [Data] {
        var out: [Data] = []
        each(sql) { out.append(Self.blob($0, 0)) }
        return out
    }

    func indexedBlobs(_ sql: String) -> [(Int, Data)] {
        var out: [(Int, Data)] = []
        each(sql) { out.append((Int(sqlite3_column_int64($0, 0)), Self.blob($0, 1))) }
        return out
    }

    func texts(_ sql: String) -> [(String, String)] {
        var out: [(String, String)] = []
        each(sql) { out.append((Self.text($0, 0), Self.text($0, 1))) }
        return out
    }
}

/// Leitor mínimo de protobuf: primeiro valor de cada campo do nível atual.
struct Proto {
    private var varints: [Int: UInt64] = [:]
    private var bytes: [Int: Data] = [:]

    init(_ data: Data) {
        let b = [UInt8](data)
        var i = 0
        func varint() -> UInt64? {
            var result: UInt64 = 0, shift: UInt64 = 0
            while i < b.count, shift < 64 {
                let c = b[i]; i += 1
                result |= UInt64(c & 0x7f) << shift
                if c < 0x80 { return result }
                shift += 7
            }
            return nil
        }
        while i < b.count, let key = varint() {
            let field = Int(key >> 3)
            switch key & 7 {
            case 0:
                guard let v = varint() else { return }
                if varints[field] == nil { varints[field] = v }
            case 1: i += 8
            case 5: i += 4
            case 2:
                guard let len = varint(), len <= UInt64(b.count - i) else { return }
                if bytes[field] == nil { bytes[field] = Data(b[i..<(i + Int(len))]) }
                i += Int(len)
            default: return
            }
        }
    }

    func int(_ field: Int) -> Int { varints[field].map { Int(truncatingIfNeeded: $0) } ?? 0 }
    func message(_ field: Int) -> Proto? { bytes[field].map(Proto.init) }
    func string(_ field: Int) -> String? {
        bytes[field].flatMap { String(data: $0, encoding: .utf8) }.flatMap { $0.isEmpty ? nil : $0 }
    }
}
