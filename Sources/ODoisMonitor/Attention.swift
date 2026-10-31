import SwiftUI

/// O que mais pede atenção numa CLI: o limite mais próximo de estourar.
struct Attention: Equatable {
    /// Fração usada, de 0 a 1.
    let value: Double
    let label: String
    let resetsAt: Date?
    var color: Color

    init(value: Double, label: String, resetsAt: Date? = nil, color: Color? = nil) {
        self.value = min(max(value, 0), 1)
        self.label = label
        self.resetsAt = resetsAt
        self.color = color ?? Severity.color(value)
    }

    /// A partir daqui o notch fechado troca o total de tokens pelo aviso.
    static let warnAt = 0.8
    var isWarning: Bool { value >= Self.warnAt }
    var percent: String { "\(Int((value * 100).rounded()))%" }
}

enum Severity {
    static func color(_ fraction: Double) -> Color {
        fraction >= 0.9 ? .red : fraction >= 0.7 ? .orange : .green
    }
}

extension UsageSnapshot {
    /// O limite mais alto informado pela CLI; nil se ela não informa limites.
    var attention: Attention? {
        guard let top = limits.max(by: { $0.usedPercent < $1.usedPercent }) else { return nil }
        return Attention(value: top.usedPercent / 100, label: top.label, resetsAt: top.resetsAt)
    }
}

extension SystemSample {
    var ramFraction: Double { ramTotal > 0 ? Double(ramUsed) / Double(ramTotal) : 0 }

    /// Memória em uso, colorida pela pressão (o que de fato deixa a máquina lenta).
    var attention: Attention {
        Attention(
            value: ramFraction,
            label: "RAM",
            color: pressureLevel == .normal ? .green : pressureLevel.color
        )
    }
}

/// Estado de uso de uma CLI a partir da última resposta registrada.
enum Activity {
    static let activeWindow: TimeInterval = 600

    static func isActive(_ last: Date?, now: Date = Date()) -> Bool {
        guard let last else { return false }
        return now.timeIntervalSince(last) < activeWindow
    }

    static func text(_ last: Date?, now: Date = Date()) -> String {
        guard let last else { return "Sem uso nos últimos 7 dias" }
        let s = now.timeIntervalSince(last)
        if s < 120 { return "Em uso agora" }
        if s < activeWindow { return "Ativo \(Format.relative(last, now: now))" }
        return "Último uso \(Format.relative(last, now: now))"
    }
}

extension Format {
    /// Pastas criadas por apps com o pedido como nome ("quero-tua-ajuda-pra-gente")
    /// viram frase ("Quero tua ajuda pra gente"); nomes comuns ficam como estão.
    static func project(_ name: String?) -> String? {
        guard let name, !name.isEmpty else { return nil }
        let words = name.split(separator: "-")
        guard words.count >= 4, name == name.lowercased(), !name.contains(" ") else { return name }
        let sentence = words.joined(separator: " ")
        return sentence.prefix(1).uppercased() + sentence.dropFirst()
    }
}
