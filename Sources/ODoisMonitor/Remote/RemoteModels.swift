import AppKit

/// Contrato JSON do acesso remoto (v1). Mudanças incompatíveis sobem a versão.
/// Datas em ISO 8601; tokens em número inteiro; frações de 0 a 1.
struct RemoteState: Encodable {
    let version = 1
    let appVersion: String
    let generatedAt: Date
    let host: String
    let providers: [RemoteProvider]
    let system: RemoteSystem
    let processes: [RemoteProcess]
    let sea: RemoteSea?
    let activeSessions: Int
}

struct RemoteProvider: Encodable {
    let id: String
    let name: String
    let tint: String
    let symbol: String
    let monogram: String?
    let hasIcon: Bool
    let account: String?
    let plan: String?
    let source: String?
    let active: Bool
    let lastActivity: Date?
    let today: RemoteTokens
    let messagesToday: Int
    let sessionsToday: Int
    let topModel: String?
    let weekTotal: Int
    let daily: [Int]
    let costToday: Double?
    let costWeek: Double?
    let limits: [RemoteLimit]
    let block: RemoteBlock?
    let sessions: [RemoteSession]
    let note: String?
}

struct RemoteTokens: Encodable {
    let total, input, output, cacheRead, cacheWrite, reasoning: Int

    init(_ t: TokenTotals) {
        total = t.total; input = t.input; output = t.output
        cacheRead = t.cacheRead; cacheWrite = t.cacheWrite; reasoning = t.reasoning
    }
}

struct RemoteLimit: Encodable {
    let label: String
    let usedPercent: Double
    let resetsAt: Date?
}

struct RemoteBlock: Encodable {
    let tokens: Int
    let endsAt: Date
}

struct RemoteSession: Encodable {
    let id: String
    let project: String?
    let model: String?
    let tokens: Int
    let messages: Int
    let cost: Double
    let last: Date
    let active: Bool
}

struct RemoteSystem: Encodable {
    let cpu: Double
    let ramUsed: UInt64
    let ramTotal: UInt64
    let swapUsed: UInt64
    let swapTotal: UInt64
    let pressure: Double
    let pressureLevel: String
    let gpu: Double?
    let cpuHistory: [Double]
    let pressureHistory: [Double]
}

struct RemoteProcess: Encodable {
    let pid: Int32
    let cli: String
    let cliName: String
    let project: String?
    let directory: String?
    let cpu: Double
    let memory: UInt64
    let startedAt: Date?
    let background: Bool
    let stopping: Bool
}

struct RemoteSea: Encodable {
    let account: String?
    let dashboardURL: String?
    let loading: Bool
    let error: String?
    let updatedAt: Date?
    let tasks: [RemoteTask]
    let timers: [RemoteTimer]
    let notifications: [RemoteNotification]
    let ranking: RemoteRanking?
    let message: String?
}

struct RemoteTask: Encodable {
    let id: Int
    let number: Int
    let subject: String
    let statusId: Int
    let inProgress: Bool
    let projectSlug: String
    let projectName: String
    let url: String?
    let busy: Bool
}

struct RemoteTimer: Encodable {
    let task: RemoteTask
    let startedAt: Date
    let accumulated: Double
    let runningSince: Date?
    let running: Bool
    /// Segundos no momento em que o estado foi gerado (o celular conta a partir daqui).
    let elapsed: Double
    let preferredActivityType: Int?
}

struct RemoteNotification: Encodable {
    let id: Int
    let title: String
    let body: String
    let actor: String?
    let url: String?
    let createdAt: Date?
}

struct RemoteRanking: Encodable {
    let year: Int
    let score: Double
    let manual: Double
    let automatic: Double
    let badges: Double
    let position: Int?
    let total: Int?
}

extension NSColor {
    /// "#RRGGBB" no espaço sRGB.
    var hex: String {
        guard let c = usingColorSpace(.sRGB) else { return "#888888" }
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}

extension NSImage {
    /// PNG quadrado no tamanho pedido (ícones e avatar para o celular).
    func png(size: CGFloat) -> Data? {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )
        guard let rep else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
