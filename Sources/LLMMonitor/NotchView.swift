import AppKit
import SwiftUI

/// Onde fica a câmera na tela: largura e altura do notch, centro e topo (coordenadas de tela).
struct NotchGeometry: Equatable {
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var centerX: CGFloat
    var top: CGFloat
    var hasNotch: Bool

    /// Tela com notch (ou a principal) e a área ocupada pela câmera.
    static func current() -> (NSScreen?, NotchGeometry) {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
        guard let screen else {
            return (nil, NotchGeometry(notchWidth: 0, notchHeight: 24, centerX: 0, top: 0, hasNotch: false))
        }
        let f = screen.frame
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let width = f.width - left.width - right.width
            return (screen, NotchGeometry(
                notchWidth: width, notchHeight: screen.safeAreaInsets.top,
                centerX: left.maxX + width / 2, top: f.maxY, hasNotch: true
            ))
        }
        // Sem notch: uma pílula no centro da barra de menus.
        let menuBar = max(f.maxY - screen.visibleFrame.maxY, 24)
        return (screen, NotchGeometry(notchWidth: 0, notchHeight: menuBar, centerX: f.midX, top: f.maxY, hasNotch: false))
    }
}

/// Medidas do notch. O NotchController usa as mesmas contas para detectar o mouse.
enum NotchMetrics {
    /// Raio das "orelhas" côncavas que unem o notch à borda da tela.
    static let ear: CGFloat = 10
    static let wingIcon: CGFloat = 18
    static let wingSpacing: CGFloat = 6
    static let wingPadding: CGFloat = 12
    static let tabIcon: CGFloat = 34
    static let tabSpacing: CGFloat = 14
    static let tabTop: CGFloat = 8
    static let minExpandedWidth: CGFloat = 372
    /// Altura da janela: comporta o notch expandido com folga.
    static let windowHeight: CGFloat = 900

    static func wing(_ count: Int) -> CGFloat {
        let n = CGFloat(max(count, 1))
        return max(64, n * wingIcon + (n - 1) * wingSpacing + wingPadding * 2)
    }

    static func collapsedWidth(_ g: NotchGeometry, _ count: Int) -> CGFloat {
        g.notchWidth + wing(count) * 2 + ear * 2
    }

    static func expandedWidth(_ g: NotchGeometry, _ count: Int) -> CGFloat {
        max(minExpandedWidth, collapsedWidth(g, count))
    }

    /// Centro da aba `index` medido a partir do canto superior esquerdo do formato expandido.
    static func tabCenter(_ index: Int, count: Int, width: CGFloat, notchHeight: CGFloat) -> CGPoint {
        let n = CGFloat(count)
        let row = n * tabIcon + (n - 1) * tabSpacing
        let x = (width - row) / 2 + CGFloat(index) * (tabIcon + tabSpacing) + tabIcon / 2
        return CGPoint(x: x, y: notchHeight + tabTop + tabIcon / 2)
    }
}

final class NotchState: ObservableObject {
    @Published var geometry = NotchGeometry(notchWidth: 0, notchHeight: 32, centerX: 0, top: 0, hasNotch: false)
    @Published var expanded = false
    @Published var contentHeight: CGFloat = 0
}

/// Formato do notch: topo reto colado na borda da tela, orelhas côncavas no alto
/// e cantos arredondados embaixo.
struct NotchShape: Shape {
    var ear: CGFloat
    var radius: CGFloat

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let r = min(radius, h / 2, (w - ear * 2) / 2)
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addQuadCurve(to: CGPoint(x: ear, y: ear), control: CGPoint(x: ear, y: 0))
        p.addLine(to: CGPoint(x: ear, y: h - r))
        p.addQuadCurve(to: CGPoint(x: ear + r, y: h), control: CGPoint(x: ear, y: h))
        p.addLine(to: CGPoint(x: w - ear - r, y: h))
        p.addQuadCurve(to: CGPoint(x: w - ear, y: h - r), control: CGPoint(x: w - ear, y: h))
        p.addLine(to: CGPoint(x: w - ear, y: ear))
        p.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w - ear, y: 0))
        p.closeSubpath()
        return p
    }
}

private struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct NotchView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var state: NotchState
    @ObservedObject var selection: CardSelection
    @ObservedObject var monitor = SystemMonitor.shared

    var body: some View {
        let g = state.geometry
        let count = store.items.count
        let width = state.expanded
            ? NotchMetrics.expandedWidth(g, count)
            : NotchMetrics.collapsedWidth(g, count)

        VStack(spacing: 0) {
            if state.expanded {
                expanded(g)
                    .transition(RenderMode.snapshot ? .identity : .opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            } else {
                collapsed(g)
                    .transition(RenderMode.snapshot ? .identity : .opacity)
            }
        }
        .frame(width: width)
        .background(NotchShape(ear: NotchMetrics.ear, radius: state.expanded ? 26 : 12).fill(Color.black))
        .background(GeometryReader { geo in Color.clear.preference(key: HeightKey.self, value: geo.size.height) })
        .onPreferenceChange(HeightKey.self) { state.contentHeight = $0 }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: state.expanded)
        .animation(.easeOut(duration: 0.2), value: selection.id)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    /// Fechado: ícones à esquerda da câmera e o total do dia à direita.
    private func collapsed(_ g: NotchGeometry) -> some View {
        let wing = NotchMetrics.wing(store.items.count)
        return HStack(spacing: 0) {
            HStack(spacing: NotchMetrics.wingSpacing) {
                ForEach(store.items) { item in
                    ProviderIcon(item: item, size: NotchMetrics.wingIcon, active: isActive(item.id))
                }
            }
            .frame(width: wing)

            Color.clear.frame(width: g.notchWidth)

            // Total de tokens do dia e um ponto com a cor da pressão de memória.
            HStack(spacing: 5) {
                Circle()
                    .fill(monitor.current.pressureLevel.color)
                    .frame(width: 6, height: 6)
                    .help("Pressão de memória: \(monitor.current.pressureLevel.label)")
                Text(Format.tokens(todayTotal))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .frame(width: wing)
        }
        .padding(.horizontal, NotchMetrics.ear)
        .frame(height: g.notchHeight)
    }

    /// Expandido: abas com as CLIs logo abaixo da câmera e o card da selecionada.
    private func expanded(_ g: NotchGeometry) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: g.notchHeight)
            HStack(spacing: NotchMetrics.tabSpacing) {
                ForEach(store.items) { item in
                    let selected = selection.id == item.id
                    ProviderIcon(item: item, size: 26, active: isActive(item.id))
                        .frame(width: NotchMetrics.tabIcon, height: NotchMetrics.tabIcon)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(selected ? 0.16 : 0))
                        )
                        .scaleEffect(selected ? 1.06 : 1)
                }
            }
            .padding(.top, NotchMetrics.tabTop)
            .frame(height: NotchMetrics.tabTop + NotchMetrics.tabIcon, alignment: .bottom)

            UsageCardView(store: store, selection: selection, embedded: true)
                .padding(.top, 8)
                .padding(.bottom, 16)
        }
        .padding(.horizontal, NotchMetrics.ear)
    }

    private var todayTotal: Int {
        store.items.reduce(0) { $0 + (store.snapshots[$1.id]?.today.total ?? 0) }
    }

    private func isActive(_ id: String) -> Bool {
        guard let last = store.snapshots[id]?.lastActivity else { return false }
        return Date().timeIntervalSince(last) < 600
    }
}
