import Foundation

/// Contrato v1 do Mac (`GET /v1/state`). Campos novos são opcionais para aceitar Macs antigos.
struct MonitorState: Codable, Equatable {
    var version: Int?
    var appVersion: String?
    var generatedAt: Date?
    var host: String?
    var providers: [Provider]
    var system: SystemInfo
    var processes: [CliProcess]
    var sea: Sea?
    var activeSessions: Int?

    var todayTotal: Int { providers.reduce(0) { $0 + $1.today.total } }

    /// O limite mais alto entre as CLIs.
    var topLimit: (provider: Provider, limit: Limit)? {
        providers.flatMap { p in p.limits.map { (p, $0) } }.max { $0.1.usedPercent < $1.1.usedPercent }
    }
}

struct Provider: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    var tint: String?
    var symbol: String?
    var monogram: String?
    var hasIcon: Bool?
    var account: String?
    var plan: String?
    var source: String?
    var active: Bool?
    var lastActivity: Date?
    var today: Tokens
    var messagesToday: Int?
    var sessionsToday: Int?
    var topModel: String?
    var weekTotal: Int?
    var daily: [Int]?
    var history: [Int]?
    var costToday: Double?
    var costWeek: Double?
    var limits: [Limit]
    var block: Block?
    var sessions: [Session]?
    var note: String?

    var isActive: Bool { active ?? false }
    var topLimit: Limit? { limits.max { $0.usedPercent < $1.usedPercent } }
}

struct Tokens: Codable, Equatable {
    var total = 0, input = 0, output = 0, cacheRead = 0, cacheWrite = 0, reasoning = 0
}

struct Limit: Codable, Equatable {
    let label: String
    let usedPercent: Double
    var resetsAt: Date?
    var forecastAt: Date?
    var fraction: Double { min(max(usedPercent / 100, 0), 1) }
}

struct Block: Codable, Equatable {
    let tokens: Int
    let endsAt: Date
}

struct Session: Codable, Equatable, Identifiable {
    let id: String
    var project: String?
    var model: String?
    var tokens: Int
    var messages: Int
    var cost: Double?
    var last: Date
    var active: Bool?
}

struct SystemInfo: Codable, Equatable {
    var cpu: Double = 0
    var ramUsed: Int64 = 0
    var ramTotal: Int64 = 0
    var swapUsed: Int64 = 0
    var swapTotal: Int64 = 0
    var pressure: Double = 0
    var pressureLevel: String = "normal"
    var gpu: Double?
    var cpuHistory: [Double]?
    var pressureHistory: [Double]?
    var ramFraction: Double { ramTotal > 0 ? Double(ramUsed) / Double(ramTotal) : 0 }
}

struct CliProcess: Codable, Equatable, Identifiable {
    let pid: Int32
    let cli: String
    let cliName: String
    var project: String?
    var directory: String?
    var cpu: Double
    var memory: Int64
    var startedAt: Date?
    var background: Bool
    var stopping: Bool?
    var id: Int32 { pid }
}

struct Sea: Codable, Equatable {
    var account: String?
    var dashboardURL: String?
    var loading: Bool?
    var error: String?
    var updatedAt: Date?
    var tasks: [SeaTask]
    var timers: [TaskTimer]
    var notifications: [SeaNotification]
    var ranking: Ranking?
    var message: String?

    var running: TaskTimer? { timers.first { $0.running } }
    var accountName: String? { account?.components(separatedBy: " · ").first }
}

struct SeaTask: Codable, Equatable, Identifiable, Hashable {
    let id: Int
    let number: Int
    let subject: String
    var statusId: Int?
    var inProgress: Bool
    let projectSlug: String
    let projectName: String
    var url: String?
    var busy: Bool?
    var title: String { "#\(number) \(subject)" }
}

struct TaskTimer: Codable, Equatable {
    let task: SeaTask
    let startedAt: Date
    var accumulated: Double
    var runningSince: Date?
    var running: Bool
    var elapsed: Double
    var preferredActivityType: Int?

    /// Segundos agora, contando a partir de quando o estado foi recebido.
    func elapsed(at now: Date, receivedAt: Date) -> Double {
        running ? elapsed + now.timeIntervalSince(receivedAt) : elapsed
    }
}

struct SeaNotification: Codable, Equatable, Identifiable {
    let id: Int
    let title: String
    var body: String?
    var actor: String?
    var url: String?
    var createdAt: Date?
}

struct Ranking: Codable, Equatable {
    let year: Int
    let score: Double
    var manual: Double?
    var automatic: Double?
    var badges: Double?
    var position: Int?
    var total: Int?
}

struct ActivityType: Codable, Equatable, Identifiable, Hashable {
    let id: Int
    let label: String
}

struct ActivityTypes: Codable {
    var data: [ActivityType]
    var preferred: Int?
}

/// Conteúdo do QR code gerado no Mac (*Parear celular…*).
struct PairingInfo: Codable, Equatable {
    var v: Int?
    let url: String
    let token: String
    var host: String?
    var device: String?

    /// Lê o JSON do QR; aceita só HTTPS e token não trivial.
    static func parse(_ raw: String) -> PairingInfo? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Link de pareamento: odoismonitor://pair?c=<JSON em base64url>.
        if let url = URL(string: text), url.scheme == "odoismonitor",
           let c = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "c" })?.value {
            var b64 = c.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            while b64.count % 4 != 0 { b64 += "=" }
            text = Data(base64Encoded: b64).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }
        guard let data = text.data(using: .utf8),
              let info = try? JSONDecoder().decode(PairingInfo.self, from: data),
              info.url.hasPrefix("https://"), info.token.count >= 20 else { return nil }
        return info
    }
}

enum MonitorJSON {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}
