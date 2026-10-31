import AppKit

/// Uma CLI de LLM que o monitor sabe ler.
protocol UsageProvider: AnyObject, Sendable {
    var id: String { get }
    var name: String { get }
    var symbol: String { get }
    /// Sigla desenhada no ícone no lugar do símbolo (ex.: "DK").
    var monogram: String? { get }
    var tint: NSColor { get }
    /// Nome do executável procurado no PATH.
    var binary: String { get }
    /// Pasta de dados que indica instalação mesmo sem achar o executável.
    var dataDirectory: URL { get }
    /// App desktop cujo ícone pode representar a CLI, se instalado.
    var appBundleNames: [String] { get }

    func load() -> UsageSnapshot
    /// Grava em disco o que estiver em cache (chamado ao fechar o app).
    func flush()
}

extension UsageProvider {
    var monogram: String? { nil }
    func flush() {}
    var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    var isInstalled: Bool {
        BinaryLocator.find(binary) != nil || FileManager.default.fileExists(atPath: dataDirectory.path)
    }

    var appIcon: NSImage? {
        for name in appBundleNames {
            for base in ["/Applications", home.appendingPathComponent("Applications").path] {
                let path = "\(base)/\(name).app"
                if FileManager.default.fileExists(atPath: path) {
                    return NSWorkspace.shared.icon(forFile: path)
                }
            }
        }
        return nil
    }
}

enum BinaryLocator {
    /// Apps abertos pelo Finder não herdam o PATH do shell; procura nos lugares comuns.
    static func find(_ name: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var dirs = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        dirs += [
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin",
            "\(home)/.local/bin", "\(home)/.claude/local", "\(home)/.npm-global/bin",
            "\(home)/.bun/bin", "\(home)/.volta/bin", "\(home)/.cargo/bin",
        ]
        for dir in dirs {
            let path = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }
}

/// Lê arquivos JSONL e guarda o resultado por arquivo até a data de modificação mudar.
final class JSONLCache {
    private struct Entry { let modified: Date; let events: [UsageEvent] }
    private var entries: [String: Entry] = [:]
    private let lock = NSLock()

    func events(for files: [URL], parse: (URL) -> [UsageEvent]) -> [UsageEvent] {
        var result: [UsageEvent] = []
        var seen = Set<String>()
        for url in files {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            lock.lock()
            let cached = entries[url.path]
            lock.unlock()
            let events: [UsageEvent]
            if let cached, cached.modified == modified {
                events = cached.events
            } else {
                events = parse(url)
                lock.lock()
                entries[url.path] = Entry(modified: modified, events: events)
                lock.unlock()
            }
            result += events
            seen.insert(url.path)
        }
        lock.lock()
        entries = entries.filter { seen.contains($0.key) }
        lock.unlock()
        return result
    }

    /// Itera as linhas de um arquivo como objetos JSON.
    static func forEachObject(in url: URL, containing marker: String? = nil, _ body: ([String: Any]) -> Void) {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return }
        let markerData = marker.map { Data($0.utf8) }
        for line in data.split(separator: UInt8(ascii: "\n")) {
            if let markerData, line.range(of: markerData) == nil { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            body(obj)
        }
    }

    /// Arquivos com uma extensão, modificados nos últimos `days` dias.
    static func recentFiles(under root: URL, ext: String, days: Int = 8) -> [URL] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        guard let it = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in it where url.pathExtension == ext {
            let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if mod >= cutoff { files.append(url) }
        }
        return files
    }
}

enum ISODate {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain = ISO8601DateFormatter()
    private static let lock = NSLock()

    static func parse(_ value: Any?) -> Date? {
        guard let s = value as? String else { return nil }
        lock.lock(); defer { lock.unlock() }
        return withFraction.date(from: s) ?? plain.date(from: s)
    }
}

func int(_ value: Any?) -> Int {
    (value as? NSNumber)?.intValue ?? 0
}
