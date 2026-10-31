import Foundation

enum Format {
    /// 1234 → "1,2 mil"; 4_500_000 → "4,5 M"; 2_100_000_000 → "2,1 bi".
    static func tokens(_ n: Int) -> String {
        let v = Double(n)
        switch abs(v) {
        case 1_000_000_000...: return compact(v / 1_000_000_000) + " bi"
        case 1_000_000...: return compact(v / 1_000_000) + " M"
        case 1_000...: return compact(v / 1_000) + " mil"
        default: return "\(n)"
        }
    }

    private static func compact(_ v: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.maximumFractionDigits = v < 10 ? 1 : 0
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.1f", v)
    }

    /// 0.3253 → "US$ 0,33"; valores pequenos com mais casas: "US$ 0,0012".
    static func usd(_ v: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = v > 0 && v < 0.01 ? 4 : 2
        return "US$ " + (f.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v))
    }

    static func relative(_ date: Date, now: Date = Date()) -> String {
        let s = Int(now.timeIntervalSince(date))
        if s < 60 { return "agora" }
        if s < 3600 { return "há \(s / 60) min" }
        if s < 86_400 { return "há \(s / 3600) h" }
        return "há \(s / 86_400) d"
    }

    /// Tempo até uma data futura: "em 2 h 15 min", "em 3 d 4 h".
    static func until(_ date: Date, now: Date = Date()) -> String {
        let s = max(0, Int(date.timeIntervalSince(now)))
        let d = s / 86_400, h = (s % 86_400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "em \(d) d \(h) h" }
        if h > 0 { return "em \(h) h \(m) min" }
        return "em \(m) min"
    }

    static func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "EEE HH:mm"
        return f.string(from: date)
    }

    /// Inicial do dia da semana para os últimos 7 dias, terminando hoje.
    static func weekdayInitials(now: Date = Date()) -> [String] {
        let cal = Calendar.current
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "EEEEE"
        return (0..<7).reversed().map { offset in
            let d = cal.date(byAdding: .day, value: -offset, to: now) ?? now
            return f.string(from: d).uppercased()
        }
    }
}
