import AppKit
import Combine
import SwiftUI

/// Janela acoplada ao notch da câmera. Fica sempre no topo da tela; o mouse é
/// consultado por timer (não exige permissão) para expandir, recolher e trocar de aba.
@MainActor
final class NotchController {
    let panel: FloatingPanel
    private let store: UsageStore
    private let state = NotchState()
    private let selection = CardSelection()
    private var timer: Timer?
    private var lastInside = Date.distantPast
    private var enteredAt: Date?
    private var cancellables = Set<AnyCancellable>()

    init(store: UsageStore) {
        self.store = store
        // Acima da barra de menus, para cobrir a faixa em volta da câmera.
        panel = FloatingPanel(level: NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3))
        panel.ignoresMouseEvents = true
        let host = NSHostingView(rootView: NotchView(store: store, state: state, selection: selection))
        host.sizingOptions = []
        panel.contentView = host

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in Task { @MainActor in self?.place() } }
            .store(in: &cancellables)
        store.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.place() } }
            .store(in: &cancellables)
    }

    func show() {
        place()
        panel.orderFrontRegardless()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        state.expanded = false
        panel.orderOut(nil)
    }

    /// Janela da largura máxima, centrada na câmera e colada no topo da tela.
    func place() {
        let (screen, g) = NotchGeometry.current()
        state.geometry = g
        // O painel comporta o maior dos dois formatos (fechado pode ser mais largo que aberto).
        let width = max(NotchMetrics.expandedWidth(g, store.items.count), NotchMetrics.collapsedWidth(g, store.items.count)) + 40
        let height = min(NotchMetrics.windowHeight, (screen?.frame.height ?? NotchMetrics.windowHeight) - 20)
        panel.setFrame(NSRect(x: g.centerX - width / 2, y: g.top - height, width: width, height: height), display: true)
    }

    /// Retângulo visível do notch agora, em coordenadas de tela.
    private func visibleRect() -> NSRect {
        let g = state.geometry
        let count = store.items.count
        let width = state.expanded ? NotchMetrics.expandedWidth(g, count) : NotchMetrics.collapsedWidth(g, count)
        let height = state.expanded ? max(state.contentHeight, g.notchHeight) : g.notchHeight
        // +2 no topo: o mouse parado na borda superior da tela também conta.
        let rect = NSRect(x: g.centerX - width / 2, y: g.top - height, width: width, height: height + 2)
        guard state.expanded else { return rect }
        // Aberto, o notch pode ficar mais estreito que a faixa fechada; a faixa continua
        // contando como "dentro" para ele não fechar e reabrir com o mouse sobre as asas.
        let strip = NotchMetrics.collapsedWidth(g, count)
        return rect.union(NSRect(x: g.centerX - strip / 2, y: g.top - g.notchHeight, width: strip, height: g.notchHeight + 2))
    }

    private func tick() {
        let mouse = NSEvent.mouseLocation
        let rect = visibleRect()
        let inside = rect.contains(mouse)
        panel.ignoresMouseEvents = !inside

        if inside {
            lastInside = Date()
            if !state.expanded {
                // Pequena espera para não abrir ao passar a caminho da barra de menus.
                if enteredAt == nil { enteredAt = Date() }
                if let t = enteredAt, Date().timeIntervalSince(t) > 0.12 { expand() }
            } else {
                selectTab(at: mouse, in: rect)
            }
        } else {
            enteredAt = nil
            if state.expanded, Date().timeIntervalSince(lastInside) > 0.35 { collapse() }
        }
    }

    private func expand() {
        // Abre sempre na visão geral: a pergunta ao chegar é "como está tudo?".
        selection.id = OverviewCardView.id
        if let id = selection.id { store.refreshIfStale(id) }
        state.expanded = true
    }

    private func collapse() {
        state.expanded = false
        enteredAt = nil
    }

    /// Passar o mouse sobre uma aba troca a CLI mostrada no card.
    private func selectTab(at mouse: CGPoint, in rect: NSRect) {
        // Medido no formato aberto (o `rect` recebido inclui a faixa fechada).
        let g = state.geometry
        let width = NotchMetrics.expandedWidth(g, store.items.count)
        let local = CGPoint(x: mouse.x - (g.centerX - width / 2), y: g.top - mouse.y)
        let tabs = NotchMetrics.tabIDs(store)
        let half = (NotchMetrics.tabIcon + NotchMetrics.tabSpacing) / 2
        for (i, id) in tabs.enumerated() {
            let c = NotchMetrics.tabCenter(i, count: tabs.count, width: width, notchHeight: g.notchHeight)
            if abs(local.x - c.x) <= half, abs(local.y - c.y) <= NotchMetrics.tabIcon / 2 + 4 {
                if selection.id != id {
                    selection.id = id
                    store.refreshIfStale(id)
                }
                return
            }
        }
    }
}
