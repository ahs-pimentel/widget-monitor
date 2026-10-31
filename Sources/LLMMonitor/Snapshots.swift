import AppKit
import SwiftUI

/// `LLMMonitor --snapshot <pasta>` desenha a barra, os cards e o notch em PNG com os dados
/// reais, sem abrir janelas nem pedir permissão de gravação de tela. Serve para conferir o
/// visual e comparar antes/depois de uma mudança.
@MainActor
enum Snapshots {
    static func render(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        RenderMode.snapshot = true
        let store = UsageStore()
        let monitor = SystemMonitor.shared
        // Espera os dados das CLIs e algumas amostras do sistema para os gráficos.
        let deadline = Date().addingTimeInterval(15)
        while (store.snapshots.count < store.items.count || monitor.history.count < 4), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        }

        var written: [String] = []
        func save<V: View>(_ name: String, _ view: V, scheme: ColorScheme) {
            let content = view
                .environment(\.colorScheme, scheme)
                .padding(24)
                .background(Backdrop(scheme: scheme))
            guard let png = renderWithAppKit(content) else {
                print("ERRO: não renderizou \(name)")
                return
            }
            let url = dir.appendingPathComponent("\(name).png")
            try? png.write(to: url)
            written.append(url.lastPathComponent)
        }

        for scheme in [ColorScheme.dark, .light] {
            let suffix = scheme == .dark ? "escuro" : "claro"
            let barState = BarState(orientation: .horizontal)
            barState.hovered = store.items.first?.id
            save("barra-\(suffix)", BarView(store: store, state: barState), scheme: scheme)

            for item in store.items {
                let selection = CardSelection()
                selection.id = item.id
                save("card-\(item.id)-\(suffix)", UsageCardView(store: store, selection: selection), scheme: scheme)
            }
        }

        // O notch é sempre preto; uma imagem fechado e uma por aba expandida.
        let (_, geometry) = NotchGeometry.current()
        let notchShots: [(String, String?)] = [("notch-fechado", nil)] + store.items.map { ("notch-\($0.id)", $0.id) }
        for (name, expandedId) in notchShots {
            let state = NotchState()
            state.geometry = geometry
            state.expanded = expandedId != nil
            let selection = CardSelection()
            selection.id = expandedId
            let width = NotchMetrics.expandedWidth(geometry, store.items.count) + 40
            let view = NotchView(store: store, state: state, selection: selection)
                .frame(width: width)
                .fixedSize(horizontal: false, vertical: true)
            save(name, view, scheme: .dark)
        }
        print("OK: \(written.count) imagens em \(dir.path)")
    }
}

/// Desenha a view por um NSHostingView numa janela fora da tela, o mesmo caminho do app.
/// (O ImageRenderer achata o vibrancy do macOS e deixa textos e ícones apagados.)
@MainActor
private func renderWithAppKit<V: View>(_ view: V) -> Data? {
    let host = NSHostingView(rootView: view)
    let size = host.fittingSize
    guard size.width > 0, size.height > 0 else { return nil }
    let window = NSWindow(
        contentRect: NSRect(origin: CGPoint(x: -10_000, y: -10_000), size: size),
        styleMask: [.borderless], backing: .buffered, defer: false
    )
    window.contentView = host
    host.frame = NSRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
    host.cacheDisplay(in: host.bounds, to: rep)
    return rep.representation(using: .png, properties: [:])
}

/// Fundo que imita a área de trabalho, para o vidro e as sombras terem contra o que aparecer.
private struct Backdrop: View {
    let scheme: ColorScheme

    var body: some View {
        LinearGradient(
            colors: scheme == .dark
                ? [Color(red: 0.16, green: 0.18, blue: 0.32), Color(red: 0.35, green: 0.22, blue: 0.45)]
                : [Color(red: 0.72, green: 0.80, blue: 0.95), Color(red: 0.93, green: 0.80, blue: 0.88)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}
