import Foundation

/// Contadores de tokens de um período.
struct TokenTotals: Equatable, Codable {
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheWrite = 0
    var reasoning = 0

    var total: Int { input + output + cacheRead + cacheWrite }

    static func + (lhs: TokenTotals, rhs: TokenTotals) -> TokenTotals {
        TokenTotals(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheRead: lhs.cacheRead + rhs.cacheRead,
            cacheWrite: lhs.cacheWrite + rhs.cacheWrite,
            reasoning: lhs.reasoning + rhs.reasoning
        )
    }

    static func += (lhs: inout TokenTotals, rhs: TokenTotals) { lhs = lhs + rhs }
}

/// Um evento de consumo: uma resposta do modelo com tokens.
struct UsageEvent: Codable {
    let date: Date
    let model: String?
    let session: String
    let tokens: TokenTotals
    /// Identificador para descartar a mesma resposta gravada em mais de um arquivo.
    var key: String? = nil
    /// Custo em US$ quando o provedor informa (ex.: OpenRouter).
    var cost: Double = 0
    /// Pasta do projeto em que a sessão rodou.
    var project: String? = nil
}

/// Consumo somado de uma sessão.
struct SessionUsage: Identifiable, Equatable {
    let id: String
    var project: String?
    var model: String?
    var tokens = TokenTotals()
    var cost = 0.0
    var messages = 0
    var first: Date
    var last: Date
    /// Tokens nos últimos 60 minutos (alerta de sessão disparando).
    var lastHourTokens = 0
    /// Maior consumo dentro de uma mesma hora do relógio nos últimos 7 dias.
    var peakHourTokens = 0
}

extension Array where Element == UsageEvent {
    func deduplicated() -> [UsageEvent] {
        var seen = Set<String>()
        return filter { e in
            guard let k = e.key else { return true }
            return seen.insert(k).inserted
        }
    }
}

/// Limite de uso reportado pela própria CLI (ex.: Codex).
struct RateLimit: Identifiable, Equatable, Codable {
    var id: String { label }
    let label: String
    let usedPercent: Double
    let resetsAt: Date?
}

/// Tudo o que o card mostra para uma CLI.
struct UsageSnapshot: Equatable {
    var today = TokenTotals()
    var week = TokenTotals()
    var messagesToday = 0
    var sessionsToday = 0
    var topModel: String?
    /// Total de tokens por dia, do mais antigo (índice 0) até hoje (índice 6).
    var daily: [Int] = Array(repeating: 0, count: 7)
    var lastActivity: Date?
    var limits: [RateLimit] = []
    /// Bloco de 5 h estimado a partir dos logs (Claude não grava o limite real).
    var blockTokens: Int?
    var blockEndsAt: Date?
    var plan: String?
    /// Conta logada na CLI (e-mail, organização ou perfil).
    var account: String?
    var note: String?
    /// Custo em US$; nil quando a CLI não registra custo.
    var costToday: Double?
    var costWeek: Double?
    /// De onde vem o consumo (ex.: "via OpenRouter").
    var source: String?
    /// Sessões com atividade nos últimos 7 dias, da mais recente para a mais antiga.
    var sessions: [SessionUsage] = []

    static let empty = UsageSnapshot()
}

enum Aggregator {
    /// Agrega eventos dos últimos 7 dias num snapshot.
    static func snapshot(from events: [UsageEvent], now: Date = Date()) -> UsageSnapshot {
        var snap = UsageSnapshot()
        let cal = Calendar.current
        let startToday = cal.startOfDay(for: now)
        guard let startWeek = cal.date(byAdding: .day, value: -6, to: startToday) else { return snap }

        var modelCount: [String: Int] = [:]
        var sessionsToday = Set<String>()
        var costToday = 0.0, costWeek = 0.0
        var sessions: [String: SessionUsage] = [:]
        var sessionModels: [String: [String: Int]] = [:]
        var sessionHours: [String: [Int: Int]] = [:]
        let lastHourStart = now.addingTimeInterval(-3600)

        for e in events where e.date >= startWeek {
            snap.week += e.tokens
            costWeek += e.cost

            var s = sessions[e.session] ?? SessionUsage(id: e.session, first: e.date, last: e.date)
            s.tokens += e.tokens
            s.cost += e.cost
            s.messages += 1
            s.first = min(s.first, e.date)
            s.last = max(s.last, e.date)
            if s.project == nil { s.project = e.project }
            if e.date >= lastHourStart { s.lastHourTokens += e.tokens.total }
            sessions[e.session] = s
            sessionHours[e.session, default: [:]][Int(e.date.timeIntervalSince1970 / 3600), default: 0] += e.tokens.total
            if let m = e.model { sessionModels[e.session, default: [:]][m, default: 0] += e.tokens.total }
            let dayIndex = cal.dateComponents([.day], from: startWeek, to: cal.startOfDay(for: e.date)).day ?? 0
            if (0..<7).contains(dayIndex) { snap.daily[dayIndex] += e.tokens.total }
            if e.date >= startToday {
                snap.today += e.tokens
                costToday += e.cost
                snap.messagesToday += 1
                sessionsToday.insert(e.session)
                if let m = e.model { modelCount[m, default: 0] += e.tokens.total }
            }
            if snap.lastActivity.map({ e.date > $0 }) ?? true { snap.lastActivity = e.date }
        }
        snap.sessionsToday = sessionsToday.count
        snap.sessions = sessions.values
            .map { s in
                var s = s
                s.model = sessionModels[s.id]?.max { $0.value < $1.value }?.key
                s.peakHourTokens = sessionHours[s.id]?.values.max() ?? 0
                return s
            }
            .sorted { $0.last > $1.last }
        if costWeek > 0 {
            snap.costToday = costToday
            snap.costWeek = costWeek
        }
        snap.topModel = modelCount.max { $0.value < $1.value }?.key
        return snap
    }

    /// Bloco de 5 h no estilo do limite do Claude: começa na hora cheia da
    /// primeira mensagem e dura 5 h; uma pausa maior que 5 h abre outro bloco.
    static func activeBlock(events: [UsageEvent], now: Date = Date()) -> (tokens: Int, endsAt: Date)? {
        let window: TimeInterval = 5 * 3600
        let sorted = events.sorted { $0.date < $1.date }
        var start: Date?
        var last: Date?
        var tokens = 0
        for e in sorted {
            if let s = start, let l = last, e.date < s.addingTimeInterval(window), e.date.timeIntervalSince(l) < window {
                tokens += e.tokens.total
            } else {
                start = Calendar.current.dateInterval(of: .hour, for: e.date)?.start ?? e.date
                tokens = e.tokens.total
            }
            last = e.date
        }
        guard let s = start else { return nil }
        let end = s.addingTimeInterval(window)
        return end > now ? (tokens, end) : nil
    }
}
