import SwiftUI

enum BarOrientation: String {
    case horizontal, vertical
}

/// Medidas fixas da barra. O AppDelegate usa as mesmas contas para posicionar o card.
enum BarMetrics {
    static let item: CGFloat = 40
    static let spacing: CGFloat = 8
    static let padding: CGFloat = 9
    /// Margem transparente em volta da cápsula para a sombra não ser cortada.
    static let inset: CGFloat = 14

    static func size(count: Int, orientation: BarOrientation) -> CGSize {
        let n = CGFloat(max(count, 1))
        let long = n * item + (n - 1) * spacing + padding * 2 + inset * 2
        let short = item + padding * 2 + inset * 2
        return orientation == .horizontal ? CGSize(width: long, height: short) : CGSize(width: short, height: long)
    }

    /// Índice do ícone sob o ponto (coordenadas da janela), ou nil se fora de um ícone.
    static func index(at point: CGPoint, count: Int, orientation: BarOrientation) -> Int? {
        for i in 0..<count {
            let c = center(of: i, count: count, orientation: orientation)
            let alongHalf = (item + spacing) / 2
            let acrossHalf = item / 2 + padding
            let (along, across) = orientation == .horizontal
                ? (abs(point.x - c.x), abs(point.y - c.y))
                : (abs(point.y - c.y), abs(point.x - c.x))
            if along <= alongHalf && across <= acrossHalf { return i }
        }
        return nil
    }

    /// Centro do ícone `index`, em coordenadas da janela (origem embaixo à esquerda).
    static func center(of index: Int, count: Int, orientation: BarOrientation) -> CGPoint {
        let size = size(count: count, orientation: orientation)
        let along = inset + padding + CGFloat(index) * (item + spacing) + item / 2
        return orientation == .horizontal
            ? CGPoint(x: along, y: size.height / 2)
            : CGPoint(x: size.width / 2, y: size.height - along)
    }
}

/// Estado da barra compartilhado com o AppDelegate (o rastreamento do mouse é feito em AppKit).
final class BarState: ObservableObject {
    @Published var hovered: String?
    @Published var orientation: BarOrientation
    init(orientation: BarOrientation) { self.orientation = orientation }
}

struct BarView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var state: BarState

    var body: some View {
        let hovered = state.hovered
        let layout = state.orientation == .horizontal
            ? AnyLayout(HStackLayout(spacing: BarMetrics.spacing))
            : AnyLayout(VStackLayout(spacing: BarMetrics.spacing))

        layout {
            if store.items.isEmpty {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 20))
                    .frame(width: BarMetrics.item, height: BarMetrics.item)
                    .help("Nenhuma CLI de LLM encontrada")
            }
            ForEach(store.items) { item in
                ProviderIcon(item: item, size: 30, active: isActive(item.id))
                    .frame(width: BarMetrics.item, height: BarMetrics.item)
                    .background {
                        Circle()
                            .fill(Color.primary.opacity(hovered == item.id ? 0.12 : 0))
                    }
                    .scaleEffect(hovered == item.id ? 1.12 : 1)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovered)
            }
        }
        .padding(BarMetrics.padding)
        .modifier(GlassCapsule())
        .padding(BarMetrics.inset)
    }

    /// Ponto verde quando houve resposta nos últimos 10 minutos.
    private func isActive(_ id: String) -> Bool {
        guard let last = store.snapshots[id]?.lastActivity else { return false }
        return Date().timeIntervalSince(last) < 600
    }
}

struct ProviderIcon: View {
    let item: UsageStore.Item
    let size: CGFloat
    var active = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let icon = item.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color(nsColor: item.provider.tint), Color(nsColor: item.provider.tint).opacity(0.7)],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .overlay {
                            if let mono = item.provider.monogram {
                                Text(mono)
                                    .font(.system(size: size * 0.38, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.white)
                            } else {
                                Image(systemName: item.provider.symbol)
                                    .font(.system(size: size * 0.46, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                }
            }
            .frame(width: size, height: size)

            if active {
                Circle()
                    .fill(Color.green)
                    .frame(width: size * 0.28, height: size * 0.28)
                    .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                    .offset(x: 2, y: 2)
            }
        }
    }
}

/// Vidro do macOS 26+ quando disponível; material translúcido nas versões anteriores.
struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.15)))
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        }
    }
}

struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.12)))
                .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
        }
    }
}
