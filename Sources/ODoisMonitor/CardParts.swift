import SwiftUI

/// Medidas únicas dos cards: a mesma margem em todos os lados e o mesmo respiro entre seções.
enum CardMetrics {
    /// Largura total do card, margens incluídas.
    static let width: CGFloat = 276
    /// Margem interna, igual nos quatro lados (barra e notch).
    static let padding: CGFloat = 14
    /// Espaço entre seções.
    static let spacing: CGFloat = 12
    /// Margem das caixas internas (limites, sistema).
    static let boxPadding: CGFloat = 10
    static let boxRadius: CGFloat = 10
}

/// Caixa de fundo apagado usada para agrupar (limites, resumo do sistema).
struct InsetBox: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(CardMetrics.boxPadding)
            .background(RoundedRectangle(cornerRadius: CardMetrics.boxRadius, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

/// Título de seção dos cards: rótulo em versalete à esquerda, detalhe opcional à direita.
struct SectionTitle: View {
    let title: String
    var detail: String?

    init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.4)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.secondary)
            Spacer()
            if let detail {
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }
}

/// Barra de progresso em cápsula com trilho apagado.
struct Meter: View {
    let value: Double
    let color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule()
                    .fill(color.gradient)
                    .frame(width: value > 0 ? max(height, geo.size.width * min(max(value, 0), 1)) : 0)
            }
        }
        .frame(height: height)
    }
}

/// Limite de uso: rótulo, percentual colorido pela faixa, barra e quando reinicia.
struct LimitRow: View {
    let attention: Attention

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(attention.label).font(.system(size: 12, weight: .medium))
                Spacer()
                Text(attention.percent)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(attention.color)
                    .monospacedDigit()
            }
            Meter(value: attention.value, color: attention.color, height: 7)
            if let eta = attention.forecast {
                Label("No ritmo atual esgota \(Format.until(eta)) · \(Format.time(eta))", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            if let reset = attention.resetsAt {
                Text("Reinicia \(Format.until(reset)) · \(Format.time(reset))")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
}

/// Uma parte de um total, para a barra de composição.
struct Segment: Identifiable {
    let label: String
    let value: Int
    let color: Color
    var id: String { label }
}

/// Barra empilhada com a proporção de cada parte e a legenda em duas colunas.
struct SegmentBar: View {
    let segments: [Segment]

    var body: some View {
        let total = max(segments.reduce(0) { $0 + $1.value }, 1)
        let visible = segments.filter { $0.value > 0 }
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let gaps = CGFloat(max(visible.count - 1, 0)) * 2
                HStack(spacing: 2) {
                    ForEach(visible) { s in
                        Rectangle()
                            .fill(s.color)
                            .frame(width: max(2, (geo.size.width - gaps) * CGFloat(s.value) / CGFloat(total)))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                ForEach(0..<(segments.count + 1) / 2, id: \.self) { row in
                    GridRow {
                        legend(segments[row * 2])
                        if row * 2 + 1 < segments.count { legend(segments[row * 2 + 1]) }
                    }
                }
            }
        }
    }

    private func legend(_ s: Segment) -> some View {
        HStack(spacing: 5) {
            Circle().fill(s.color).frame(width: 6, height: 6)
            Text(s.label).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(Format.tokens(s.value)).fontWeight(.semibold).monospacedDigit()
        }
        .font(.system(size: 10))
    }
}

/// Ponto verde e texto de atividade ("Em uso agora", "Último uso há 3 h").
struct ActivityLabel: View {
    let last: Date?

    var body: some View {
        let active = Activity.isActive(last)
        HStack(spacing: 4) {
            if active {
                Circle().fill(Color.green).frame(width: 6, height: 6)
            }
            Text(Activity.text(last))
                .foregroundStyle(active ? Color.green : Color.secondary)
        }
        .font(.system(size: 11))
    }
}

/// Selo pequeno em cápsula (plano da assinatura, origem do consumo).
struct Badge: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.3)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Capsule().fill(Color.primary.opacity(0.1)))
    }
}
