import SwiftUI

/// Paleta do oDois Monitor (a mesma do Mac e do Android).
enum Palette {
    static let background = Color(red: 0.043, green: 0.043, blue: 0.078)
    static let surface = Color(red: 0.082, green: 0.082, blue: 0.122)
    static let surfaceHigh = Color(red: 0.118, green: 0.118, blue: 0.169)
    static let teal = Color(red: 0.051, green: 0.620, blue: 0.780)
    static let indigo = Color(red: 0.329, green: 0.298, blue: 0.922)
    static let secondary = Color(red: 0.604, green: 0.604, blue: 0.682)
    static let hero = LinearGradient(colors: [teal, indigo], startPoint: .topLeading, endPoint: .bottomTrailing)

    static func severity(_ fraction: Double) -> Color {
        fraction >= 0.9 ? .red : fraction >= 0.7 ? .orange : .green
    }

    static func hex(_ value: String?) -> Color {
        guard let value, value.hasPrefix("#"), let n = UInt32(value.dropFirst(), radix: 16) else { return secondary }
        return Color(red: Double((n >> 16) & 0xFF) / 255, green: Double((n >> 8) & 0xFF) / 255, blue: Double(n & 0xFF) / 255)
    }

    /// Cor estável por projeto (mesmo hash do Mac e do Android).
    static func project(_ slug: String) -> Color {
        var sum: UInt32 = 7
        for scalar in slug.unicodeScalars { sum = sum &* 31 &+ scalar.value }
        return Color(hue: Double(sum % 360) / 360, saturation: 0.6, brightness: 0.85)
    }

    static func pressure(_ level: String) -> Color {
        level == "critical" ? .red : level == "warning" ? .yellow : .green
    }
}

/// Formatação em pt-BR, igual à do Mac.
enum Fmt {
    private static let br = Locale(identifier: "pt_BR")

    private static func compact(_ v: Double) -> String {
        v.formatted(.number.locale(br).precision(.fractionLength(0...(v < 10 ? 1 : 0))))
    }

    static func tokens(_ n: Int) -> String {
        let v = Double(n)
        switch abs(v) {
        case 1_000_000_000...: return compact(v / 1e9) + " bi"
        case 1_000_000...: return compact(v / 1e6) + " M"
        case 1_000...: return compact(v / 1e3) + " mil"
        default: return "\(n)"
        }
    }

    static func usd(_ v: Double) -> String {
        "US$ " + v.formatted(.number.locale(br).precision(.fractionLength(2...(v > 0 && v < 0.01 ? 4 : 2))))
    }

    static func number(_ v: Double) -> String {
        v.formatted(.number.locale(br).precision(.fractionLength(0...2)))
    }

    static func percent(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))%" }

    static func bytes(_ b: Int64) -> String {
        let gb = Double(b) / 1_073_741_824
        return gb >= 1 ? compact(gb) + " GB" : compact(Double(b) / 1_048_576) + " MB"
    }

    static func relative(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "—" }
        let s = Int(now.timeIntervalSince(date))
        if s < 60 { return "agora" }
        if s < 3600 { return "há \(s / 60) min" }
        if s < 86_400 { return "há \(s / 3600) h" }
        return "há \(s / 86_400) d"
    }

    static func until(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "—" }
        let s = max(0, Int(date.timeIntervalSince(now)))
        let d = s / 86_400, h = (s % 86_400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "em \(d) d \(h) h" }
        if h > 0 { return "em \(h) h \(m) min" }
        return "em \(m) min"
    }

    static func time(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = DateFormatter()
        f.locale = br
        f.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "EEE HH:mm"
        return f.string(from: date)
    }

    /// 3725 s → "1:02:05"; abaixo de 1 h → "2:05".
    static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    static func activity(_ last: Date?, now: Date = Date()) -> String {
        guard let last else { return "Sem uso nos últimos 7 dias" }
        let s = now.timeIntervalSince(last)
        if s < 120 { return "Em uso agora" }
        if s < 600 { return "Ativo \(relative(last, now: now))" }
        return "Último uso \(relative(last, now: now))"
    }

    static func weekdays(now: Date = Date()) -> [String] {
        let f = DateFormatter()
        f.locale = br
        f.dateFormat = "EEEEE"
        return (0..<7).reversed().map { f.string(from: Calendar.current.date(byAdding: .day, value: -$0, to: now) ?? now).uppercased() }
    }
}
