import AppKit

/// Borda da tela onde a barra pode ficar colada.
enum ScreenEdge: String {
    case left, right, top, bottom

    /// Nas laterais a barra fica em pé; em cima e embaixo, deitada.
    var orientation: BarOrientation {
        switch self {
        case .left, .right: return .vertical
        case .top, .bottom: return .horizontal
        }
    }
}

enum EdgeSnap {
    /// Folga visível entre a cápsula e a borda quando a barra está colada.
    static let margin: CGFloat = 4
    /// Quanto da cápsula continua visível quando ela se esconde na borda.
    static let peek: CGFloat = 5
    /// Largura da faixa junto à borda que traz a barra de volta.
    static let trigger: CGFloat = 6

    static func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    /// Borda mais próxima do centro da janela.
    static func nearestEdge(to frame: NSRect, in area: NSRect) -> ScreenEdge {
        let distances: [(ScreenEdge, CGFloat)] = [
            (.left, frame.midX - area.minX),
            (.right, area.maxX - frame.midX),
            (.bottom, frame.midY - area.minY),
            (.top, area.maxY - frame.midY),
        ]
        return distances.min { $0.1 < $1.1 }!.0
    }

    /// Janela colada na borda, mantendo a posição ao longo dela (`center`).
    static func shownFrame(size: CGSize, edge: ScreenEdge, center: CGPoint, area: NSRect) -> NSRect {
        let inset = BarMetrics.inset
        var origin = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        switch edge {
        case .left: origin.x = area.minX - inset + margin
        case .right: origin.x = area.maxX - size.width + inset - margin
        case .bottom: origin.y = area.minY - inset + margin
        case .top: origin.y = area.maxY - size.height + inset - margin
        }
        // Mantém a cápsula inteira dentro da área ao longo da borda.
        origin.x = min(max(origin.x, area.minX - inset), area.maxX - size.width + inset)
        origin.y = min(max(origin.y, area.minY - inset), area.maxY - size.height + inset)
        return NSRect(origin: origin, size: size)
    }

    /// A mesma janela empurrada para fora da tela, deixando só `peek` pontos da cápsula.
    static func hiddenFrame(from shown: NSRect, edge: ScreenEdge) -> NSRect {
        let capsule = shown.insetBy(dx: BarMetrics.inset, dy: BarMetrics.inset)
        var f = shown
        switch edge {
        case .left: f.origin.x -= capsule.width + margin - peek
        case .right: f.origin.x += capsule.width + margin - peek
        case .bottom: f.origin.y -= capsule.height + margin - peek
        case .top: f.origin.y += capsule.height + margin - peek
        }
        return f
    }

    /// Faixa junto à borda, na extensão da barra, que a faz reaparecer. Vai até a borda
    /// física da tela (`full`), mesmo quando o Dock ou a barra de menus ocupam aquele lado.
    static func triggerZone(for shown: NSRect, edge: ScreenEdge, area: NSRect, full: NSRect) -> NSRect {
        let capsule = shown.insetBy(dx: BarMetrics.inset, dy: BarMetrics.inset)
        let depth = trigger + peek
        switch edge {
        case .left:
            return NSRect(x: full.minX, y: capsule.minY, width: area.minX - full.minX + depth, height: capsule.height)
        case .right:
            return NSRect(x: area.maxX - depth, y: capsule.minY, width: full.maxX - area.maxX + depth, height: capsule.height)
        case .bottom:
            return NSRect(x: capsule.minX, y: full.minY, width: capsule.width, height: area.minY - full.minY + depth)
        case .top:
            return NSRect(x: capsule.minX, y: area.maxY - depth, width: capsule.width, height: full.maxY - area.maxY + depth)
        }
    }
}
