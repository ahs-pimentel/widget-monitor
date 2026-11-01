import Foundation

/// Previsão de esgotamento dos limites: guarda o percentual usado ao longo do tempo
/// (por CLI, limite e janela) e projeta, no ritmo das últimas horas, quando chega a 100%.
@MainActor
enum LimitTrend {
    private struct Sample: Codable {
        let at: Date
        let percent: Double
    }

    private static let key = "limitSamples"
    /// Janela usada no ritmo e o mínimo de tempo entre a primeira e a última amostra.
    static let window: TimeInterval = 3 * 3600
    static let minimumSpan: TimeInterval = 15 * 60

    private static var samples: [String: [Sample]] = {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode([String: [Sample]].self, from: data) else { return [:] }
        return saved
    }()

    /// Registra os limites do snapshot e devolve-os com a previsão preenchida.
    static func apply(provider: String, limits: [RateLimit], now: Date = Date()) -> [RateLimit] {
        guard !limits.isEmpty else { return limits }
        let result = limits.map { limit -> RateLimit in
            let id = "\(provider):\(limit.label):\(limit.resetsAt.map { String(Int($0.timeIntervalSince1970)) } ?? "-")"
            var list = (samples[id] ?? []).filter { now.timeIntervalSince($0.at) < window }
            // Uma amostra por minuto basta (o snapshot chega a cada 60 s ou no hover).
            if list.last.map({ now.timeIntervalSince($0.at) >= 60 }) ?? true {
                list.append(Sample(at: now, percent: limit.usedPercent))
            }
            samples[id] = list
            var copy = limit
            copy.forecast = forecast(list, limit: limit, now: now)
            return copy
        }
        // Esquece janelas que já passaram.
        samples = samples.filter { $0.value.last.map { now.timeIntervalSince($0.at) < window } ?? false }
        if let data = try? JSONEncoder().encode(samples) { UserDefaults.standard.set(data, forKey: key) }
        return result
    }

    /// Momento em que chega a 100% no ritmo atual; nil se não sobe, se já esgotou
    /// ou se só esgotaria depois de o limite reiniciar.
    private static func forecast(_ list: [Sample], limit: RateLimit, now: Date) -> Date? {
        guard limit.usedPercent < 100, let first = list.first, let last = list.last,
              last.at.timeIntervalSince(first.at) >= minimumSpan, last.percent > first.percent else { return nil }
        let perSecond = (last.percent - first.percent) / last.at.timeIntervalSince(first.at)
        let eta = now.addingTimeInterval((100 - last.percent) / perSecond)
        if let reset = limit.resetsAt, eta >= reset { return nil }
        return eta
    }
}

/// Histórico diário de tokens por CLI (até 90 dias). Os logs só são lidos 7 dias para trás;
/// cada dia visto fica guardado, então o histórico cresce dia a dia a partir da instalação.
@MainActor
enum DailyHistory {
    private static let key = "dailyHistory"
    static let keepDays = 90

    private static var store: [String: [String: Int]] = {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: [String: Int]]) ?? [:]
    }()

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Grava os 7 dias do snapshot (o de hoje é sobrescrito a cada leitura).
    static func record(provider: String, daily: [Int], now: Date = Date()) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var days = store[provider] ?? [:]
        for (i, total) in daily.enumerated() {
            guard let date = cal.date(byAdding: .day, value: i - (daily.count - 1), to: today) else { continue }
            let key = formatter.string(from: date)
            // Dias passados não diminuem (um log apagado não deve zerar o histórico).
            days[key] = i == daily.count - 1 ? total : max(days[key] ?? 0, total)
        }
        if let cutoff = cal.date(byAdding: .day, value: -keepDays, to: today) {
            let limit = formatter.string(from: cutoff)
            days = days.filter { $0.key >= limit }
        }
        store[provider] = days
        UserDefaults.standard.set(store, forKey: key)
    }

    /// Totais dos últimos `days` dias, do mais antigo até hoje (0 onde não há dado).
    static func last(_ days: Int, provider: String, now: Date = Date()) -> [Int] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let saved = store[provider] ?? [:]
        return (0..<days).map { i in
            guard let date = cal.date(byAdding: .day, value: i - (days - 1), to: today) else { return 0 }
            return saved[formatter.string(from: date)] ?? 0
        }
    }

    /// Quantos dias do período têm dado guardado (para dizer "histórico desde …").
    static func coverage(_ days: Int, provider: String) -> Int {
        last(days, provider: provider).filter { $0 > 0 }.count
    }
}
