import AppKit
import SwiftUI

extension NSWindow.Level {
    /// Acima da barra de menus, para cobrir a faixa em volta da câmera.
    static let notch = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
}

extension NSAlert {
    /// Mostra o alerta acima do notch e dos cards; no nível normal ele ficava escondido
    /// atrás do painel aberto, sem como clicar.
    @MainActor
    @discardableResult
    func runAboveMonitor() -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        window.level = NSWindow.Level(rawValue: NSWindow.Level.notch.rawValue + 1)
        return runModal()
    }
}

/// Painel flutuante sem borda que não rouba o foco do app em uso.
final class FloatingPanel: NSPanel {
    init(level: NSWindow.Level) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = level
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Conteúdo da barra: informa o ponto sob o cursor (o arraste fica no AppDelegate)
/// em coordenadas da janela (origem embaixo à esquerda, igual ao BarMetrics).
final class BarHostingView<Content: View>: NSHostingView<Content> {
    var onMouseMoved: ((CGPoint?) -> Void)?

    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        onMouseMoved?(event.locationInWindow)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onMouseMoved?(event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onMouseMoved?(nil)
    }

    // O vidro do SwiftUI cria subviews nativas que capturariam o clique;
    // a barra não tem controles clicáveis, então todo clique fica com esta view.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = superview.map { convert(point, from: $0) } ?? point
        return bounds.contains(local) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
