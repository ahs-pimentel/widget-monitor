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
    static let tabIcon: CGFloat = 30
    static let tabSpacing: CGFloat = 8
    static let tabTop: CGFloat = 6
    /// Aberto, o notch tem a largura do card (mais as orelhas), não a da faixa fechada.
    static let minExpandedWidth: CGFloat = CardMetrics.width + ear * 2
    /// Altura da janela: comporta o notch expandido com folga.
    static let windowHeight: CGFloat = 900

    /// Largura mínima da asa: cabe o histórico de CPU, a barra de RAM e o total de tokens.
    static let minWing: CGFloat = 128

    static func wing(_ count: Int) -> CGFloat {
        let n = CGFloat(max(count, 1))
        return max(minWing, n * wingIcon + (n - 1) * wingSpacing + wingPadding * 2)
    }

    /// Espaço extra nas asas para o cronômetro de tarefa quando há um rodando.
    static let timerWidth: CGFloat = 64

    /// `timer` nil = estado atual do cronômetro; true = pior caso (para dimensionar o painel).
    @MainActor static func collapsedWidth(_ g: NotchGeometry, _ count: Int, timer: Bool? = nil) -> CGFloat {
        let extra = (timer ?? (SeaStore.shared.running != nil)) ? timerWidth : 0
        return g.notchWidth + (wing(count) + extra) * 2 + ear * 2
    }

    /// Aberto, há uma aba a mais: a visão geral, antes das CLIs.
    static func expandedWidth(_ g: NotchGeometry, _ count: Int) -> CGFloat {
        let tabs = CGFloat(count + 1)
        let row = tabs * tabIcon + (tabs - 1) * tabSpacing + (CardMetrics.padding + ear) * 2
        return max(minExpandedWidth, g.notchWidth + ear * 2 + 24, row)
    }

    /// Abas do notch aberto, na ordem em que aparecem.
    @MainActor static func tabIDs(_ store: UsageStore) -> [String] {
        [OverviewCardView.id] + store.items.map(\.id)
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
    @ObservedObject var sea = SeaStore.shared

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
        let wing = NotchMetrics.wing(store.items.count) + (sea.running != nil ? NotchMetrics.timerWidth : 0)
        return HStack(spacing: 0) {
            HStack(spacing: NotchMetrics.wingSpacing) {
                ForEach(store.items) { item in
                    ProviderIcon(item: item, size: NotchMetrics.wingIcon, active: isActive(item.id))
                }
                if let running = sea.running {
                    // Cronômetro da tarefa em andamento, à vista sem abrir o notch.
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        HStack(spacing: 3) {
                            Image(systemName: "timer").font(.system(size: 9, weight: .bold))
                            Text(SeaStore.clock(running.elapsed(now: ctx.date)))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .monospacedDigit()
                        }
                        .foregroundStyle(Color(nsColor: SeaProvider().tint).opacity(1))
                        .brightness(0.25)
                    }
                    .help(running.task.title)
                }
            }
            .frame(width: wing)

            Color.clear.frame(width: g.notchWidth)

            // Processamento e memória em miniatura e, ao lado, o total de tokens do dia —
            // ou o limite que está perto de estourar, que é o que importa ver sem abrir.
            HStack(spacing: 6) {
                if activeSessions.total > 0 {
                    HStack(spacing: 3) {
                        Circle().fill(Color.green).frame(width: 5, height: 5)
                        Text("\(activeSessions.total)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    .foregroundStyle(.green)
                    .help(activeSessions.summary)
                }
                CollapsedSystemMeters(monitor: monitor)
                if let (name, warning) = topWarning {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9))
                        Text(warning.percent)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    .foregroundStyle(warning.color)
                    .help("\(name): \(warning.label.lowercased()) em \(warning.percent)")
                } else {
                    Text(Format.tokens(todayTotal))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .monospacedDigit()
                        .lineLimit(1)
                }
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
                OverviewIcon(size: 24)
                    .frame(width: NotchMetrics.tabIcon, height: NotchMetrics.tabIcon)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(selection.id == OverviewCardView.id ? 0.16 : 0))
                    )
                    .scaleEffect(selection.id == OverviewCardView.id ? 1.06 : 1)
                ForEach(store.items) { item in
                    let selected = selection.id == item.id
                    ProviderIcon(item: item, size: 22, active: isActive(item.id), ring: ring(for: item.id))
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
        }
        .padding(.horizontal, NotchMetrics.ear)
    }

    private var todayTotal: Int {
        store.items.reduce(0) { $0 + (store.snapshots[$1.id]?.today.total ?? 0) }
    }

    private func isActive(_ id: String) -> Bool {
        if id == SeaProvider.identifier { return sea.running != nil }
        return Activity.isActive(store.snapshots[id]?.lastActivity)
    }

    private func ring(for id: String) -> Attention? {
        id == SystemProvider.identifier ? monitor.current.attention : store.snapshots[id]?.attention
    }

    /// Sessões com resposta nos últimos 10 min, no total e por CLI (para o tooltip).
    private var activeSessions: (total: Int, summary: String) {
        let perCLI = store.items.compactMap { item -> (String, Int)? in
            let n = store.snapshots[item.id]?.sessions.filter { Activity.isActive($0.last) }.count ?? 0
            return n > 0 ? (item.provider.name, n) : nil
        }
        let total = perCLI.reduce(0) { $0 + $1.1 }
        let summary = "\(total) \(total == 1 ? "sessão ativa" : "sessões ativas") (últimos 10 min)\n"
            + perCLI.map { "\($0.0): \($0.1)" }.joined(separator: "\n")
        return (total, summary)
    }

    /// O limite mais alto entre as CLIs, se passou do ponto de aviso.
    private var topWarning: (String, Attention)? {
        store.items
            .compactMap { item in store.snapshots[item.id]?.attention.map { (item.provider.name, $0) } }
            .filter { $0.1.isWarning }
            .max { $0.1.value < $1.1.value }
    }
}

/// Notch fechado: histórico curto de CPU e barra de RAM colorida pela pressão de memória.
struct CollapsedSystemMeters: View {
    @ObservedObject var monitor: SystemMonitor
    static let cpuSamples = 10

    var body: some View {
        let s = monitor.current
        let cpu = Array(monitor.history.suffix(Self.cpuSamples).map(\.cpu))
        let padded = Array(repeating: 0.0, count: max(0, Self.cpuSamples - cpu.count)) + cpu
        let ram = s.ramTotal > 0 ? Double(s.ramUsed) / Double(s.ramTotal) : 0
        let ramColor: Color = s.pressureLevel == .normal ? .purple : s.pressureLevel.color

        HStack(alignment: .bottom, spacing: 5) {
            HStack(alignment: .bottom, spacing: 1) {
                ForEach(padded.indices, id: \.self) { i in
                    bar(padded[i], color: .blue, width: 2)
                }
            }
            bar(ram, color: ramColor, width: 5)
        }
        .frame(height: Self.height)
        .help(
            "CPU \(Int((s.cpu * 100).rounded()))% · RAM \(Bytes.format(s.ramUsed)) de \(Bytes.format(s.ramTotal))"
                + " · pressão \(s.pressureLevel.label.lowercased())"
        )
    }

    static let height: CGFloat = 14

    /// Trilho apagado com o preenchimento de baixo para cima (mínimo de 1 pt para não sumir).
    private func bar(_ value: Double, color: Color, width: CGFloat) -> some View {
        let v = min(max(value, 0), 1)
        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.12))
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(height: max(1, Self.height * v))
        }
        .frame(width: width, height: Self.height)
    }
}

/// Ícone da aba de visão geral.
struct OverviewIcon: View {
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(
                colors: [Color(red: 0.36, green: 0.30, blue: 0.95), Color(red: 0.58, green: 0.28, blue: 0.85)],
                startPoint: .top, endPoint: .bottom
            ))
            .overlay(
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: size * 0.44, weight: .bold))
                    .foregroundStyle(.white)
            )
            .frame(width: size, height: size)
    }
}
