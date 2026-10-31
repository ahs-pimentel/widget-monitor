import AppKit
import Combine
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = UsageStore()
    let selection = CardSelection()
    let alerts = AlertCenter()
    lazy var barState = BarState(
        orientation: BarOrientation(rawValue: UserDefaults.standard.string(forKey: Keys.orientation) ?? "") ?? .horizontal
    )

    var bar: FloatingPanel!
    var card: FloatingPanel!
    var cardHost: NSHostingController<UsageCardView>!
    var hideWork: DispatchWorkItem?
    var dragging = false
    var cancellables = Set<AnyCancellable>()

    enum Keys {
        static let origin = "barOrigin"
        static let orientation = "barOrientation"
        static let autoHide = "barAutoHide"
        static let snap = "barSnapToEdge"
        static let edge = "barEdge"
        static let notch = "notchMode"
    }

    // Modo notch: em vez da barra flutuante, o monitor fica acoplado à câmera.
    var notchMode = UserDefaults.standard.bool(forKey: Keys.notch)
    lazy var notch = NotchController(store: store)

    // Colar na borda: ao soltar, a barra gruda na borda mais próxima da tela.
    var snapToEdge = UserDefaults.standard.bool(forKey: Keys.snap)
    var dockedEdge = ScreenEdge(rawValue: UserDefaults.standard.string(forKey: Keys.edge) ?? "")
    var dockedScreen: NSScreen?
    /// Centro da barra ao longo da borda (só o eixo paralelo à borda importa).
    var dockCenter = CGPoint.zero

    // Auto-ocultar: a barra some e reaparece quando o mouse encosta na área dela.
    var autoHide = UserDefaults.standard.bool(forKey: Keys.autoHide)
    var proximityTimer: Timer?
    var lastNear = Date()
    var barShown = true

    func applicationWillTerminate(_ notification: Notification) {
        store.flush()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildBar()
        buildCard()

        store.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.resizeBar() }
            .store(in: &cancellables)
        // O card muda de altura quando o snapshot chega; reposiciona em seguida.
        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in DispatchQueue.main.async { self?.layoutCard() } }
            .store(in: &cancellables)
        // Alertas: reavalia quando chegam dados novos das CLIs ou do sistema.
        let monitor = SystemMonitor.shared
        Publishers.CombineLatest(store.$snapshots, monitor.$current)
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] snapshots, system in
                guard let self else { return }
                let names = Dictionary(uniqueKeysWithValues: store.items.map { ($0.id, $0.provider.name) })
                alerts.handle(AlertRules.evaluate(
                    snapshots: snapshots, names: names, system: system, processes: monitor.processes
                ))
            }
            .store(in: &cancellables)

        restoreDock()
        applyAutoHide()
        installDragMonitor()
        if notchMode { enterNotch() }
    }

    // MARK: - Notch

    func enterNotch() {
        proximityTimer?.invalidate()
        proximityTimer = nil
        setHovered(nil, immediate: true)
        bar.orderOut(nil)
        notch.show()
    }

    func exitNotch() {
        notch.hide()
        bar.orderFrontRegardless()
        applyAutoHide()
    }

    @objc func toggleNotch() {
        notchMode.toggle()
        UserDefaults.standard.set(notchMode, forKey: Keys.notch)
        notchMode ? enterNotch() : exitNotch()
        rebuildMenu()
    }

    // MARK: - Colar na borda

    var isDocked: Bool { snapToEdge && dockedEdge != nil }

    func dockGeometry() -> (edge: ScreenEdge, shown: NSRect, area: NSRect, full: NSRect)? {
        guard snapToEdge, let edge = dockedEdge,
              let screen = dockedScreen ?? bar.screen ?? NSScreen.main else { return nil }
        let size = BarMetrics.size(count: store.items.count, orientation: barState.orientation)
        let shown = EdgeSnap.shownFrame(size: size, edge: edge, center: dockCenter, area: screen.visibleFrame)
        return (edge, shown, screen.visibleFrame, screen.frame)
    }

    /// Ao abrir o app, volta para a borda onde a barra estava.
    func restoreDock() {
        guard isDocked, let edge = dockedEdge else { return }
        dockCenter = CGPoint(x: bar.frame.midX, y: bar.frame.midY)
        dockedScreen = EdgeSnap.screen(containing: dockCenter)
        setOrientation(edge.orientation)
        placeDocked(animate: false)
    }

    /// Cola na borda mais próxima da tela onde está o mouse (ou a barra).
    func dock(near point: CGPoint) {
        guard let screen = EdgeSnap.screen(containing: point) else { return }
        dockedScreen = screen
        let edge = EdgeSnap.nearestEdge(to: bar.frame, in: screen.visibleFrame)
        dockedEdge = edge
        UserDefaults.standard.set(edge.rawValue, forKey: Keys.edge)
        dockCenter = CGPoint(x: bar.frame.midX, y: bar.frame.midY)
        setOrientation(edge.orientation)
        placeDocked(animate: true)
    }

    /// Posiciona a barra colada: inteira na borda ou, se escondida, só com uma faixa visível.
    func placeDocked(animate: Bool) {
        guard let g = dockGeometry() else { return }
        let target = barShown ? g.shown : EdgeSnap.hiddenFrame(from: g.shown, edge: g.edge)
        if animate {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                bar.animator().setFrame(target, display: true)
            }
        } else {
            bar.setFrame(target, display: true)
        }
        UserDefaults.standard.set(NSStringFromPoint(g.shown.origin), forKey: Keys.origin)
    }

    func setOrientation(_ orientation: BarOrientation) {
        guard barState.orientation != orientation else { return }
        barState.orientation = orientation
        UserDefaults.standard.set(orientation.rawValue, forKey: Keys.orientation)
        rebuildMenu()
    }

    @objc func toggleSnap() {
        snapToEdge.toggle()
        UserDefaults.standard.set(snapToEdge, forKey: Keys.snap)
        lastNear = Date()
        if snapToEdge {
            dock(near: CGPoint(x: bar.frame.midX, y: bar.frame.midY))
        } else {
            let shown = dockGeometry()?.shown
            dockedEdge = nil
            UserDefaults.standard.removeObject(forKey: Keys.edge)
            setBarShown(true)
            if let shown { bar.setFrame(clamped(shown), display: true) }
            saveOrigin()
        }
        rebuildMenu()
    }

    // MARK: - Arrastar

    var dragMonitor: Any?
    var dragOffset: CGPoint?
    var didDrag = false

    /// Intercepta o mouse destinado à barra antes de qualquer view: o arraste funciona
    /// independentemente das subviews que o SwiftUI ou o vidro colocam por cima.
    func installDragMonitor() {
        dragMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            if notchMode, event.window === notch.panel, event.type == .rightMouseDown {
                if let view = notch.panel.contentView {
                    NSMenu.popUpContextMenu(makeMenu(), with: event, for: view)
                }
                return nil
            }
            guard event.window === self.bar else { return event }
            let mouse = NSEvent.mouseLocation
            switch event.type {
            case .leftMouseDown:
                dragOffset = CGPoint(x: mouse.x - bar.frame.minX, y: mouse.y - bar.frame.minY)
                didDrag = false
            case .leftMouseDragged:
                guard let offset = dragOffset else { return nil }
                if !didDrag {
                    didDrag = true
                    dragging = true
                    setHovered(nil, immediate: true)
                }
                bar.setFrameOrigin(CGPoint(x: mouse.x - offset.x, y: mouse.y - offset.y))
            case .leftMouseUp:
                dragOffset = nil
                if didDrag {
                    didDrag = false
                    dragging = false
                    lastNear = Date()
                    if snapToEdge {
                        dock(near: mouse)
                    } else {
                        bar.setFrame(clamped(bar.frame), display: true)
                        saveOrigin()
                    }
                }
            case .rightMouseDown:
                if let view = bar.contentView { NSMenu.popUpContextMenu(makeMenu(), with: event, for: view) }
            default:
                return event
            }
            return nil
        }
    }

    // MARK: - Auto-ocultar

    func applyAutoHide() {
        proximityTimer?.invalidate()
        proximityTimer = nil
        if notchMode { return }
        if autoHide {
            lastNear = Date()
            // Consulta a posição do mouse 10x por segundo; não exige permissão de acessibilidade.
            proximityTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.checkProximity() }
            }
        } else {
            setBarShown(true)
        }
    }

    func checkProximity() {
        let mouse = NSEvent.mouseLocation
        let zone: NSRect
        if let g = dockGeometry() {
            zone = barShown
                ? g.shown.insetBy(dx: BarMetrics.inset - 6, dy: BarMetrics.inset - 6)
                : EdgeSnap.triggerZone(for: g.shown, edge: g.edge, area: g.area, full: g.full)
        } else {
            zone = bar.frame.insetBy(dx: BarMetrics.inset - 6, dy: BarMetrics.inset - 6)
        }
        let near = zone.contains(mouse) || dragging || selection.id != nil
        if near {
            lastNear = Date()
            setBarShown(true)
        } else if barShown, Date().timeIntervalSince(lastNear) > 0.8 {
            setBarShown(false)
        }
    }

    func setBarShown(_ shown: Bool) {
        guard shown != barShown else { return }
        barShown = shown
        // Escondida, a barra deixa os cliques passarem para o app de baixo.
        bar.ignoresMouseEvents = !shown
        if isDocked {
            // Colada: desliza para fora da tela e deixa uma faixa visível.
            bar.alphaValue = 1
            placeDocked(animate: true)
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = shown ? 0.15 : 0.3
            bar.animator().alphaValue = shown ? 1 : 0
        }
    }

    @objc func toggleAutoHide() {
        autoHide.toggle()
        UserDefaults.standard.set(autoHide, forKey: Keys.autoHide)
        applyAutoHide()
        rebuildMenu()
    }

    // MARK: - Barra

    func buildBar() {
        bar = FloatingPanel(level: .statusBar)
        bar.delegate = self
        let host = BarHostingView(rootView: BarView(store: store, state: barState))
        host.onMouseMoved = { [weak self] point in self?.mouseMoved(point) }
        host.menu = makeMenu()
        // O tamanho e a posição das janelas são calculados aqui, não pelo conteúdo SwiftUI.
        host.sizingOptions = []
        bar.contentView = host

        let size = BarMetrics.size(count: store.items.count, orientation: barState.orientation)
        bar.setFrame(NSRect(origin: initialOrigin(for: size), size: size), display: true)
        bar.orderFrontRegardless()
    }

    func initialOrigin(for size: CGSize) -> CGPoint {
        if let saved = UserDefaults.standard.string(forKey: Keys.origin) {
            let p = NSPointFromString(saved)
            let frame = NSRect(origin: p, size: size)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) { return p }
        }
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return CGPoint(x: screen.midX - size.width / 2, y: screen.minY + 16)
    }

    func resizeBar() {
        guard let bar else { return }
        if isDocked { return placeDocked(animate: true) }
        let size = BarMetrics.size(count: store.items.count, orientation: barState.orientation)
        var frame = bar.frame
        // Mantém o canto superior esquerdo fixo ao mudar de tamanho.
        frame.origin.y += frame.height - size.height
        frame.size = size
        bar.setFrame(clamped(frame), display: true, animate: true)
        saveOrigin()
    }

    func clamped(_ frame: NSRect) -> NSRect {
        guard let screen = (bar.screen ?? NSScreen.main)?.visibleFrame else { return frame }
        var f = frame
        f.origin.x = min(max(f.origin.x, screen.minX - BarMetrics.inset), screen.maxX - f.width + BarMetrics.inset)
        f.origin.y = min(max(f.origin.y, screen.minY - BarMetrics.inset), screen.maxY - f.height + BarMetrics.inset)
        return f
    }

    func saveOrigin() {
        UserDefaults.standard.set(NSStringFromPoint(bar.frame.origin), forKey: Keys.origin)
    }

    func windowDidMove(_ notification: Notification) {
        // Colada, a posição salva é a da barra visível (gravada em placeDocked).
        if !dragging && !isDocked { saveOrigin() }
        layoutCard()
    }

    // MARK: - Hover e card

    func mouseMoved(_ point: CGPoint?) {
        guard !dragging else { return }
        guard let point,
              let i = BarMetrics.index(at: point, count: store.items.count, orientation: barState.orientation)
        else { return setHovered(nil) }
        setHovered(store.items[i].id)
    }

    func setHovered(_ id: String?, immediate: Bool = false) {
        hideWork?.cancel()
        if let id {
            barState.hovered = id
            if selection.id != id {
                selection.id = id
                store.refreshIfStale(id)
            }
            showCard()
        } else {
            barState.hovered = nil
            let work = DispatchWorkItem { [weak self] in self?.hideCard() }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (immediate ? 0 : 0.15), execute: work)
        }
    }

    func buildCard() {
        card = FloatingPanel(level: .popUpMenu)
        card.ignoresMouseEvents = true
        card.alphaValue = 0
        cardHost = NSHostingController(rootView: UsageCardView(store: store, selection: selection))
        // A janela não se redimensiona sozinha; o tamanho vem de sizeThatFits em layoutCard.
        cardHost.sizingOptions = []
        card.contentView = cardHost.view
    }

    func showCard() {
        layoutCard()
        if !card.isVisible || card.alphaValue < 1 {
            card.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                card.animator().alphaValue = 1
            }
        }
    }

    func hideCard() {
        selection.id = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            card.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                if self?.selection.id == nil { self?.card.orderOut(nil) }
            }
        })
    }

    /// Coloca o card ao lado do ícone em foco, do lado com mais espaço na tela.
    func layoutCard() {
        guard let card, let id = selection.id,
              let index = store.items.firstIndex(where: { $0.id == id }) else { return }
        let size = cardHost.sizeThatFits(in: CGSize(
            width: UsageCardView.width + BarMetrics.inset * 2,
            height: 2000
        ))
        guard size.width > 0, size.height > 0 else { return }
        let screen = (bar.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let local = BarMetrics.center(of: index, count: store.items.count, orientation: barState.orientation)
        let anchor = CGPoint(x: bar.frame.minX + local.x, y: bar.frame.minY + local.y)
        // 8 pt visíveis entre a cápsula e o card (os dois têm margem transparente `inset`).
        let gap: CGFloat = 8 - BarMetrics.inset
        let barShort = BarMetrics.item / 2 + BarMetrics.padding

        var origin: CGPoint
        if barState.orientation == .horizontal {
            let above = anchor.y + barShort + gap
            let below = anchor.y - barShort - gap - size.height
            origin = CGPoint(
                x: anchor.x - size.width / 2,
                y: above + size.height <= screen.maxY + BarMetrics.inset ? above : below
            )
        } else {
            let right = anchor.x + barShort + gap
            let left = anchor.x - barShort - gap - size.width
            origin = CGPoint(
                x: right + size.width <= screen.maxX + BarMetrics.inset ? right : left,
                y: anchor.y - size.height / 2
            )
        }
        origin.x = min(max(origin.x, screen.minX - BarMetrics.inset), screen.maxX - size.width + BarMetrics.inset)
        origin.y = min(max(origin.y, screen.minY - BarMetrics.inset), screen.maxY - size.height + BarMetrics.inset)
        card.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}
